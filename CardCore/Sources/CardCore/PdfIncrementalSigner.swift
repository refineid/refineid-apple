// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Appends one signature or document-timestamp revision to a PDF
/// (ISO 32000-1 §7.5.6 incremental updates, §12.8 signatures; ETSI
/// EN 319 142-1 for the PAdES entries).
///
/// The original bytes are never touched: a revision is appended, and
/// what it adds is a signature dictionary with a reserved hole, an
/// invisible widget carrying it, the page and form objects reissued
/// to reference that widget, and a cross-reference section pointing
/// back at the previous one. That is what makes the result a
/// legitimate later revision of the same document rather than a new
/// document that resembles it.
public enum PdfIncrementalSigner {
  /// What a signature revision claims in its dictionary.
  public struct SignatureClaim: Sendable {
    /// The claimed signing time, written to `/M`.
    public let signedAt: Date

    /// The stated reason, when the signer gave one.
    public let reason: String?

    /// The stated place, when the signer gave one.
    public let location: String?

    /// Composes a claim.
    public init(signedAt: Date, reason: String?, location: String?) {
      self.signedAt = signedAt
      self.reason = reason
      self.location = location
    }
  }

  /// Which kind of revision to prepare.
  public enum Revision {
    /// A document timestamp: no `/M`, no `/Reason`, no `/Name` -
    /// EN 319 142-1 §5.4.3 forbids them, the token is the time.
    case documentTimestamp

    /// A qualified signature: CAdES-detached, carrying its claimed
    /// signing time in `/M` (the CMS must not carry one).
    case signature(SignatureClaim)

    /// What a signature revision claims, or nil for a timestamp.
    internal var signatureClaim: SignatureClaim? {
      switch self {
      case .documentTimestamp:
        nil

      case .signature(let claim):
        claim
      }
    }
  }

  /// The literal that opens the byte-range array.
  internal static let byteRangeArrayPrefix = "/ByteRange ["

  /// The literal that opens the hex hole.
  internal static let contentsPrefix = "/Contents "

  /// The reserved, fixed-width byte-range array.
  internal static var byteRangePlaceholder: String {
    let field = " " + String(repeating: "0", count: PdfValues.byteRangeDigits)
    let fields = String(
      repeating: field, count: PdfValues.byteRangeFieldCount
    )
    return byteRangeArrayPrefix + fields + " ]\n"
  }

  /// Prepares the revision and patches its byte ranges.
  public static func prepare(
    _ document: Data,
    revision: Revision
  ) throws -> PdfSignaturePlaceholder {
    try Self.prepare(document, revision: revision, appending: nil)
  }

  /// The same, showing the signature's visible mark.
  ///
  /// The mark is the signature widget's own appearance, laid over the
  /// last page's margin. An appearance is not page content: it adds
  /// nothing to what an earlier signature covered, so a second signer
  /// can leave a mark without breaking the first one.
  public static func prepare(
    _ document: Data,
    revision: Revision,
    appending stamp: StampMark?
  ) throws -> PdfSignaturePlaceholder {
    let index = try PdfDocumentIndex.parse(document)
    guard
      let rootNumber = PdfDocumentIndex.reference(named: "/Root", in: index.trailer),
      let size = PdfDocumentIndex.integer(named: "/Size", in: index.trailer)
    else {
      throw PdfSigningError.structureUnreadable
    }
    let signatureNumber = max(size, 1)
    let numbers = PageNumbers(firstFree: signatureNumber)
    let capacity = Self.capacity(for: revision)

    var out = Self.newlineTerminated(document)
    var offsets: [Int: Int] = [:]
    let holes = Self.appendSignatureObject(
      into: &out,
      offsets: &offsets,
      revision: revision,
      number: signatureNumber,
      capacity: capacity
    )
    let source = RevisionSource(
      document: document, index: index, rootNumber: rootNumber
    )
    let effectiveStamp = Self.effectiveStamp(stamp, source: source)
    offsets[numbers.field] = out.count
    out.append(
      try Self.fieldObject(
        revision: revision,
        source: source,
        numbers: numbers,
        signature: signatureNumber,
        stamp: effectiveStamp
      )
    )
    let highest = try Self.appendRevisionBody(
      into: &out,
      offsets: &offsets,
      source: source,
      numbers: numbers,
      stamp: effectiveStamp
    )
    try Self.closeRevision(
      into: &out,
      offsets: offsets,
      size: highest + 1,
      rootNumber: rootNumber,
      index: index
    )
    return Self.patched(
      document: out, holes: holes, capacity: capacity
    )
  }

  /// The document, ending in a newline so what follows starts on a
  /// line of its own.
  private static func newlineTerminated(_ document: Data) -> Data {
    guard document.last != UInt8(ascii: "\n") else { return document }
    var out = document
    out.append(UInt8(ascii: "\n"))
    return out
  }

  /// The signature field, showing its mark when there is one.
  ///
  /// The mark is the field's own appearance, so the field has to know
  /// where it sits before it is written.
  private static func fieldObject(
    revision: Revision,
    source: RevisionSource,
    numbers: PageNumbers,
    signature: Int,
    stamp: StampMark?
  ) throws -> Data {
    let placement = try stamp.map { mark in
      try Self.stampPlacement(source: source, stamp: mark)
    }
    let pageNumber: Int
    if let placement {
      pageNumber = placement.page
    } else {
      guard
        let catalog = source.index.body(of: source.rootNumber, in: source.document)
      else {
        throw PdfSigningError.structureUnreadable
      }
      pageNumber = try Self.firstPage(
        index: source.index, document: source.document, catalog: catalog
      )
    }
    return Data(
      Self.widget(
        revision,
        field: numbers.field,
        signature: signature,
        page: pageNumber,
        showing: placement.map { found in
          (rectangle: found.rectangle, appearance: numbers.appearance)
        }
      ).utf8
    )
  }

  /// Appends the cross-reference section and trailer.
  private static func closeRevision(
    into out: inout Data,
    offsets: [Int: Int],
    size: Int,
    rootNumber: Int,
    index: PdfDocumentIndex
  ) throws {
    let xrefOffset = out.count
    out.append(
      try Self.crossReferenceSection(
        offsets: offsets,
        size: size,
        rootNumber: rootNumber,
        xrefOffset: xrefOffset,
        index: index
      )
    )
  }

  /// Patches the byte ranges now that the file's length is final.
  private static func patched(
    document: Data,
    holes: (byteRangeAt: Int, contentsOpen: Int),
    capacity: Int
  ) -> PdfSignaturePlaceholder {
    var out = document
    let hexLength = capacity * PdfValues.hexCharactersPerByte
    let secondSpanStart = holes.contentsOpen + 1 + hexLength + 1
    Self.patchByteRange(
      into: &out,
      at: holes.byteRangeAt,
      values: [
        0, holes.contentsOpen, secondSpanStart, out.count - secondSpanStart,
      ]
    )
    return PdfSignaturePlaceholder(
      document: out,
      contentsOpen: holes.contentsOpen,
      secondSpanStart: secondSpanStart,
      capacity: capacity
    )
  }

  /// Writes the four values into the reserved array, right-aligned
  /// in their fixed-width fields so nothing moves.
  private static func patchByteRange(
    into document: inout Data,
    at offset: Int,
    values: [Int]
  ) {
    let stride = PdfValues.byteRangeDigits + 1
    for (index, value) in values.enumerated() {
      let text = String(value)
      let padded =
        String(
          repeating: " ", count: PdfValues.byteRangeDigits - text.count
        ) + text
      let start = offset + index * stride + 1
      for (position, byte) in padded.utf8.enumerated() {
        document[start + position] = byte
      }
    }
  }
}
