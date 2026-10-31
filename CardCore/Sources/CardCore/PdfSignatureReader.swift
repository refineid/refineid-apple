// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Locates the signatures of an existing PDF (ISO 32000-1 section 12.8).
///
/// The byte ranges declared by each signature dictionary define the two
/// signed spans and, between them, the hex hole carrying the CMS; the
/// reader trusts the declaration only after checking it against the
/// file's actual bytes: the hole is exactly this dictionary's own
/// `/Contents` string, and everything after the DER inside it is zero
/// padding (ISO 32000-1 clause 12.8.1).
public enum PdfSignatureReader {
  /// One signature found in the document.
  public struct FoundSignature: Sendable {
    /// The CMS ContentInfo carried in the hole, padding removed.
    public let cms: Data

    /// The declared /SubFilter.
    public let subFilter: PdfSubFilter

    /// The two declared byte-range spans.
    internal let signedSpans: PdfSignaturePlaceholder

    /// Whether the spans cover the entire file, which the final
    /// signature of a document always does.
    public let coversWholeDocument: Bool

    /// Whether the spans end where a revision ends: just after an
    /// `%%EOF` marker and at most one end-of-line (ISO 32000-1 clause
    /// 7.5.5).
    public let endsRevision: Bool

    /// The digest of the two declared byte-range spans.
    public func byteRangeDigest(_ algorithm: DocumentDigestAlgorithm) -> Data {
      signedSpans.digest(algorithm)
    }
  }

  /// Why a located signature could not be read.
  public enum Failure: Error, Sendable {
    case documentTooLarge
    case malformedByteRange
    case malformedContents
  }

  /// A signature /ByteRange declares two spans as four integers.
  private static let byteRangeEntryCount = 4

  /// The value of the first hex digit above nine.
  private static let hexLetterBase: UInt8 = 10

  /// The byte every unused position of the decoded hole holds.
  private static let contentsPadding: UInt8 = 0

  /// The end-of-line spellings that may follow `%%EOF`, longest first.
  private static let endOfLineSpellings: [[UInt8]] = [
    [PdfValues.carriageReturnByte, PdfValues.lineFeedByte],
    [PdfValues.lineFeedByte],
    [PdfValues.carriageReturnByte],
  ]

  /// Every readable signature in the document, in object order.
  ///
  /// Objects without both /ByteRange and /Contents are not signatures
  /// and are skipped; a signature candidate whose declaration does not
  /// match the file throws instead of degrading into a partial answer.
  public static func signatures(
    in document: Data
  ) throws -> [FoundSignature] {
    try Self.signatures(in: document, maximumByteCount: PdfValues.maximumVerifiedDocumentByteCount)
  }

  /// The same, refusing a document longer than `maximumByteCount`
  /// before any of it is read.
  internal static func signatures(
    in input: Data,
    maximumByteCount: Int
  ) throws -> [FoundSignature] {
    guard input.count <= maximumByteCount else { throw Failure.documentTooLarge }
    // Every offset below counts from the first byte of the file.
    let document = Data(input)
    let index = try PdfDocumentIndex.parse(document)
    var found: [FoundSignature] = []
    for number in index.locations.keys.sorted() {
      guard
        let body = index.body(of: number, in: document),
        body.contains("/ByteRange"), body.contains("/Contents")
      else { continue }
      guard let syntax = try? PdfValidationStore.DictionarySyntax(body) else {
        // Only a stream object can carry the names without being one
        // dictionary; a signature dictionary carries no stream.
        if body.contains("stream") { continue }
        throw Failure.malformedByteRange
      }
      guard
        syntax.entry(named: "ByteRange") != nil,
        let contents = syntax.entry(named: "Contents")
      else { continue }
      let contentsInFile = try Self.fileRange(
        of: contents.valueRange,
        body: body,
        location: index.locations[number],
        in: document
      )
      found.append(
        try signature(
          declaredBy: body,
          syntax: syntax,
          contentsInFile: contentsInFile,
          in: document
        )
      )
    }
    return found
  }

  /// Where a dictionary value sits in the file, for a dictionary that
  /// is a direct object; a dictionary inside an object stream has no
  /// bytes of its own in the file and cannot name a hole.
  private static func fileRange(
    of valueRange: Range<Int>,
    body: String,
    location: PdfDocumentIndex.ObjectLocation?,
    in document: Data
  ) throws -> Range<Int> {
    guard case .direct(let offset) = location else {
      throw Failure.malformedContents
    }
    let bytes = PdfBytes(document)
    guard
      let objRange = bytes.firstRange(of: "obj", from: offset),
      let bodyBytes = body.data(using: .isoLatin1)
    else {
      throw Failure.malformedContents
    }
    let bodyStart = bytes.skippingWhitespace(from: objRange.upperBound)
    guard
      bytes.data(in: bodyStart..<(bodyStart + bodyBytes.count)) == bodyBytes
    else {
      throw Failure.malformedContents
    }
    return (bodyStart + valueRange.lowerBound)..<(bodyStart + valueRange.upperBound)
  }

  private static func signature(
    declaredBy body: String,
    syntax: PdfValidationStore.DictionarySyntax,
    contentsInFile: Range<Int>,
    in document: Data
  ) throws -> FoundSignature {
    let range = PdfDocumentIndex.integerArray(named: "ByteRange", in: body)
    var entries = range.makeIterator()
    guard
      range.count == Self.byteRangeEntryCount,
      let firstStart = entries.next(),
      let holeStart = entries.next(),
      let holeEnd = entries.next(),
      let tailLength = entries.next(),
      firstStart == 0,
      holeStart > 0,
      holeEnd > holeStart,
      tailLength >= 0,
      holeEnd <= document.count,
      tailLength <= document.count - holeEnd
    else {
      throw Failure.malformedByteRange
    }
    guard holeStart..<holeEnd == contentsInFile else {
      throw Failure.malformedByteRange
    }
    let end = holeEnd + tailLength
    // The declared spans end where this signature's revision ended;
    // later revisions are not covered and must not be digested.
    let placeholder = PdfSignaturePlaceholder(
      document: document.prefix(end),
      contentsOpen: holeStart,
      secondSpanStart: holeEnd,
      capacity: 0
    )
    return FoundSignature(
      cms: try contents(inHole: holeStart..<holeEnd, of: document),
      subFilter: subFilter(in: syntax),
      signedSpans: placeholder,
      coversWholeDocument: end == document.count,
      endsRevision: Self.endsRevision(document.prefix(end))
    )
  }

  /// Whether `signed` ends with `%%EOF` and at most one end-of-line.
  internal static func endsRevision(_ signed: Data) -> Bool {
    let bytes = [UInt8](signed)
    let markerEnd =
      Self.endOfLineSpellings
      .first { bytes.count >= $0.count && bytes.suffix($0.count).elementsEqual($0) }
      .map { bytes.dropLast($0.count) } ?? bytes[...]
    let marker = Array(PdfValues.endOfFileMarker.utf8)
    return markerEnd.count >= marker.count
      && markerEnd.suffix(marker.count).elementsEqual(marker)
  }

  /// The declared /SubFilter, other when absent or not a name.
  private static func subFilter(
    in syntax: PdfValidationStore.DictionarySyntax
  ) -> PdfSubFilter {
    guard let entry = syntax.entry(named: "SubFilter") else { return .other }
    let value = syntax.value(of: entry)
    guard value.hasPrefix("/") else { return .other }
    return PdfSubFilter(name: String(value.dropFirst()))
  }

  /// Decodes the hex string filling the hole, which runs from its `<`
  /// to its `>`, and trims it to the one DER element it carries after
  /// checking that every byte behind the element is zero padding.
  private static func contents(
    inHole hole: Range<Int>,
    of document: Data
  ) throws -> Data {
    guard
      document[hole.lowerBound] == UInt8(ascii: "<"),
      document[hole.upperBound - 1] == UInt8(ascii: ">")
    else {
      throw Failure.malformedContents
    }
    var decoded = Data()
    var pending: UInt8?
    for cursor in (hole.lowerBound + 1)..<(hole.upperBound - 1) {
      guard let value = hexValue(of: document[cursor]) else {
        throw Failure.malformedContents
      }
      if let high = pending {
        decoded.append(high << PdfValues.hexDigitBits | value)
        pending = nil
      } else {
        pending = value
      }
    }
    guard pending == nil else { throw Failure.malformedContents }
    var reader = DerReader(decoded)
    guard let element = reader.next() else {
      throw Failure.malformedContents
    }
    guard
      decoded[element.raw.upperBound...].allSatisfy({ $0 == Self.contentsPadding })
    else {
      throw Failure.malformedContents
    }
    return decoded.subdata(in: element.raw)
  }

  private static func hexValue(of byte: UInt8) -> UInt8? {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"):
      byte - UInt8(ascii: "0")

    case UInt8(ascii: "A")...UInt8(ascii: "F"):
      byte - UInt8(ascii: "A") + Self.hexLetterBase

    case UInt8(ascii: "a")...UInt8(ascii: "f"):
      byte - UInt8(ascii: "a") + Self.hexLetterBase

    default:
      nil
    }
  }
}
