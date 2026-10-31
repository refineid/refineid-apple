// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// The incremental-update writer's invariants (ISO 32000-1 §7.5.6,
/// §12.8): the original survives byte-for-byte, the hole is exactly
/// what the byte ranges exclude, and filling it moves nothing.
@Suite
internal struct PdfIncrementalSignerTests {
  /// The smallest structurally complete PDF: catalog, page tree, one
  /// page, a classic cross-reference table and a trailer.
  internal static var minimalPdf: Data {
    Self.pdf(catalog: "<< /Type /Catalog /Pages 2 0 R >>")
  }

  /// One claim, for the tests that do not care what it says.
  private static var claim: PdfIncrementalSigner.SignatureClaim {
    PdfIncrementalSigner.SignatureClaim(
      signedAt: Date(timeIntervalSince1970: 0), reason: nil, location: nil
    )
  }

  /// Builds the minimal document with a caller-supplied catalog.
  private static func pdf(catalog: String) -> Data {
    var text = "%PDF-1.7\n"
    var offsets: [Int] = []
    for (number, body) in [
      (1, catalog),
      (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
      (3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>"),
    ] {
      offsets.append(text.utf8.count)
      text += "\(number) 0 obj\n\(body)\nendobj\n"
    }
    let xrefOffset = text.utf8.count
    text += "xref\n0 4\n0000000000 65535 f \n"
    for offset in offsets {
      text += String(format: "%010d 00000 n \n", offset)
    }
    text += "trailer\n<< /Size 4 /Root 1 0 R >>\n"
    text += "startxref\n\(xrefOffset)\n%%EOF\n"
    return Data(text.utf8)
  }

  /// The document as Latin-1, the way the writer reads it.
  private static func text(_ document: Data) -> String {
    String(bytes: document, encoding: .isoLatin1) ?? ""
  }

  /// The first number written after `label`, or nil.
  private static func number(after label: String, in document: Data) -> Double? {
    let text = Self.text(document)
    guard let found = text.range(of: label) else { return nil }
    let rest = text[found.upperBound...]
    let digits = rest.prefix { "0123456789.-".contains($0) || $0 == " " }
    return Double(
      digits.trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? ""
    )
  }

  /// Every form-field name the document carries, in the order written.
  private static func fieldNames(in document: Data) -> [String] {
    var found: [String] = []
    var rest = Substring(Self.text(document))
    while let opened = rest.range(of: "/T (") {
      rest = rest[opened.upperBound...]
      guard let closed = rest.firstIndex(of: ")") else { break }
      found.append(String(rest[rest.startIndex..<closed]))
      rest = rest[closed...]
    }
    return found
  }

  @Test
  internal func theOriginalBytesSurviveUnchanged() throws {
    // An incremental update appends; a reader of the earlier revision
    // must still see exactly what was there.
    let original = Self.minimalPdf
    let prepared = try PdfIncrementalSigner.prepare(
      original,
      revision: .signature(
        PdfIncrementalSigner.SignatureClaim(
          signedAt: Date(timeIntervalSince1970: 0), reason: nil, location: nil
        )
      )
    )
    #expect(prepared.document.prefix(original.count) == original)
    #expect(prepared.document.count > original.count)
  }

  @Test
  internal func reissuedObjectsPreserveRawEightBitBytes() throws {
    let marker = Data("(raw-X-byte)".utf8)
    var original = Self.pdf(
      catalog: "<< /Type /Catalog /Pages 2 0 R /Note (raw-X-byte) >>"
    )
    let markerRange = try #require(original.range(of: marker))
    let byteIndex = markerRange.lowerBound + Data("(raw-".utf8).count
    original[byteIndex] = 0xE9

    let prepared = try PdfIncrementalSigner.prepare(
      original, revision: .documentTimestamp
    )

    let rawByteCount = prepared.document.reduce(into: 0) { count, byte in
      if byte == 0xE9 { count += 1 }
    }
    #expect(rawByteCount == 2)
    #expect(!prepared.document.contains(Data([0xC3, 0xA9])))
  }

  @Test
  internal func theByteRangesExcludeExactlyTheHole() throws {
    // What is not signed must be the hex hole and nothing else:
    // everything before `<` and everything after `>`.
    let prepared = try PdfIncrementalSigner.prepare(
      Self.minimalPdf,
      revision: .signature(
        PdfIncrementalSigner.SignatureClaim(
          signedAt: Date(timeIntervalSince1970: 0), reason: nil, location: nil
        )
      )
    )
    let covered = prepared.signedOctets.count
    let hole = prepared.document.count - covered
    // The excluded region is the hex string plus its two brackets.
    let reserved = 49_152
    #expect(hole == reserved * 2 + 2)
    let text = Self.text(prepared.document)
    #expect(text.contains("/SubFilter /ETSI.CAdES.detached"))
    #expect(text.contains("/Type /Sig"))
    #expect(text.hasSuffix("%%EOF\n"))
  }

  @Test
  internal func fillingTheHoleMovesNothing() throws {
    // The digest is taken with the hole in place, so writing into it
    // must not change one offset or one length.
    let prepared = try PdfIncrementalSigner.prepare(
      Self.minimalPdf,
      revision: .signature(
        PdfIncrementalSigner.SignatureClaim(
          signedAt: Date(timeIntervalSince1970: 0), reason: nil, location: nil
        )
      )
    )
    let before = prepared.digest(QualifiedDocumentCms.signingDigestAlgorithm)
    let filled = try prepared.filled(with: WireHex.data("30030101FF"))
    #expect(filled.count == prepared.document.count)
    #expect(Self.text(filled).contains("30030101FF"))
    // The signed spans are untouched by the fill.
    let after = filled.prefix(prepared.signedOctets.count)
    #expect(after.prefix(8) == prepared.document.prefix(8))
    #expect(!before.isEmpty)
  }

  @Test
  internal func anOversizedStructureIsRefusedNotTruncated() throws {
    let prepared = try PdfIncrementalSigner.prepare(
      Self.minimalPdf, revision: .documentTimestamp
    )
    let oversized = Data(repeating: 0xAB, count: 16_385)
    #expect(throws: PdfSigningError.signatureTooLarge(needed: 16_385, reserved: 16_384)) {
      _ = try prepared.filled(with: oversized)
    }
  }

  @Test
  internal func aDocumentTimestampCarriesNoClaimedTime() throws {
    // EN 319 142-1 §5.4.3: a document timestamp's dictionary has no
    // /M, /Reason, /Name or /Location - the token is the time.
    let prepared = try PdfIncrementalSigner.prepare(
      Self.minimalPdf, revision: .documentTimestamp
    )
    let text = Self.text(prepared.document)
    #expect(text.contains("/Type /DocTimeStamp"))
    #expect(text.contains("/SubFilter /ETSI.RFC3161"))
    #expect(!text.contains("/M (D:"))
    #expect(!text.contains("/Reason"))
  }

  @Test
  internal func aSecondSignatureGetsItsOwnFieldName() throws {
    // Two form fields with the same fully qualified name are one field
    // (ISO 32000-1 §12.7.3.2). Signing a signed document with a
    // repeated name therefore gives that one name two signature
    // dictionaries, and a validator resolving it reaches the first -
    // reporting the second as inconsistent between the signed and the
    // final revision, which is what a co-signature earned until the
    // name was made unique.
    let once = try PdfIncrementalSigner.prepare(
      Self.minimalPdf, revision: .signature(Self.claim)
    )
    let signed = try once.filled(with: WireHex.data("30030101FF"))
    let twice = try PdfIncrementalSigner.prepare(
      signed, revision: .signature(Self.claim)
    )
    let names = Self.fieldNames(in: twice.document)
    #expect(names.count == 2)
    #expect(Set(names).count == 2)
  }

  @Test
  internal func aTimestampFieldDoesNotCollideWithAnEarlierOne() throws {
    // The same rule, for the archive timestamps an LTA signature adds
    // on every round.
    let once = try PdfIncrementalSigner.prepare(
      Self.minimalPdf, revision: .documentTimestamp
    )
    let stamped = try once.filled(with: WireHex.data("30030101FF"))
    let twice = try PdfIncrementalSigner.prepare(
      stamped, revision: .documentTimestamp
    )
    #expect(Set(Self.fieldNames(in: twice.document)).count == 2)
  }

  @Test
  internal func anEncryptedDocumentIsRefused() {
    var text = Self.text(Self.minimalPdf)
    text = text.replacingOccurrences(
      of: "<< /Size 4 /Root 1 0 R >>",
      with: "<< /Size 4 /Root 1 0 R /Encrypt 9 0 R >>"
    )
    #expect(throws: PdfSigningError.encrypted) {
      _ = try PdfIncrementalSigner.prepare(
        Data(text.utf8), revision: .documentTimestamp
      )
    }
  }

  @Test
  internal func somethingThatIsNotAPdfIsRefused() {
    #expect(throws: PdfSigningError.notAPdf) {
      _ = try PdfIncrementalSigner.prepare(
        Data("not a document".utf8), revision: .documentTimestamp
      )
    }
  }

  /// A stroked ring is cut off unless its box is wider than it is.
  ///
  /// An appearance is clipped to its bounding box, and a stroke
  /// straddles the path it follows - so a box measured to the mark's
  /// radius shaves the outermost ring flat on every side it touches.
  /// The widget's rectangle must leave the same room, or the reader
  /// clips what the box allowed.
  @Test
  internal func aMarksBoxLeavesRoomForItsOwnStroke() throws {
    let radius = 64.0
    let mark = StampMark(radius: radius, operators: "0 0 m 1 1 l S\n")
    let prepared = try PdfIncrementalSigner.prepare(
      Self.minimalPdf, revision: .signature(Self.claim), appending: mark
    )
    let boxLeft = try #require(Self.number(after: "/BBox [", in: prepared.document))
    #expect(boxLeft < -radius)
    #expect(mark.reach > radius)
    #expect(boxLeft == -mark.reach)
  }

  /// When multiple signatures are appended, only the first signature gets a stamp mark.
  @Test
  internal func onlyFirstSignatureAppendsStampMark() throws {
    let radius = 64.0
    let mark = StampMark(radius: radius, operators: "0 0 m 1 1 l S\n")
    let firstSigned = try PdfIncrementalSigner.prepare(
      Self.minimalPdf, revision: .signature(Self.claim), appending: mark
    )
    let filledFirst = try firstSigned.filled(with: WireHex.data("30030101FF"))
    let secondSigned = try PdfIncrementalSigner.prepare(
      filledFirst, revision: .signature(Self.claim), appending: mark
    )
    let firstCount = Self.text(firstSigned.document).components(separatedBy: "/BBox [").count - 1
    let secondCount = Self.text(secondSigned.document).components(separatedBy: "/BBox [").count - 1
    #expect(firstCount == 1)
    #expect(secondCount == 1)
  }
}
