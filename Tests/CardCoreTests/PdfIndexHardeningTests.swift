// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// Regression tests for `PdfDocumentIndex`, `PdfStreamObject`, and
  /// `PdfSignatureReader`: token-aware dictionary lookups, `/Prev` and
  /// `/Encrypt` chain safety, historical signature retention, indirect
  /// object header checks, and cross-reference bounds.
  @Suite
  internal struct PdfIndexHardeningTests {
    /// Inside every synthetic certificate's validity window.
    private static let currentTime = "20260601000000Z"

    /// Expected offset value in synthetic lookup tests.
    private static let realPrevOffset = 128

    /// Expected object number in synthetic reference lookup tests.
    private static let realRootObject = 3

    /// Expected length value in synthetic lookup tests.
    private static let realLength = 42

    /// Expected array element count for `/W`.
    private static let expectedWidthCount = 3

    /// Wrong object number used to test header mismatch rejection.
    private static let mismatchedObjectNumber = 99

    /// Expected signature count when an earlier signature is overwritten
    /// in a later revision.
    private static let twoSignatures = 2

    /// PNG Up predictor identifier in `/DecodeParms`.
    private static let pngUpPredictor = 12

    /// Compressed empty zlib stream (`78 9c 03 00 00 00 00 01`).
    private static let emptyZlibBytes: [UInt8] = [
      0x78, 0x9C, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01,
    ]

    /// Builds a twice-signed document whose intermediate revision overwrote
    /// the first signature dictionary's object number.
    private static func overwrittenSignatureDocument(
      _ fixture: DocumentTrustFixture
    ) throws -> Data {
      let contents = DocumentTrustFixture.Contents(
        cmsCertificates: [fixture.issuing]
      )
      let first = try fixture.document(contents)
      let firstIndex = try PdfDocumentIndex.parse(first)
      let firstSigNumber = try #require(
        firstIndex.locations.keys.sorted().first { number in
          firstIndex.body(of: number, in: first)?.contains("/ByteRange") == true
        }
      )
      let root = try #require(
        PdfDocumentIndex.reference(named: "/Root", in: firstIndex.trailer)
      )
      let size = try #require(
        PdfDocumentIndex.integer(named: "/Size", in: firstIndex.trailer)
      )
      var wiped = first
      if wiped.last != UInt8(ascii: "\n") {
        wiped.append(UInt8(ascii: "\n"))
      }
      let wipeOffset = wiped.count
      wiped.append(
        Data("\(firstSigNumber) 0 obj\n<< /Type /Annot >>\nendobj\n".utf8)
      )
      let wipeXref = wiped.count
      wiped.append(
        try PdfIncrementalSigner.crossReferenceSection(
          offsets: [firstSigNumber: wipeOffset],
          size: size,
          rootNumber: root,
          xrefOffset: wipeXref,
          index: firstIndex
        )
      )
      let claim = PdfIncrementalSigner.SignatureClaim(
        signedAt: Date(timeIntervalSince1970: 0), reason: nil, location: nil
      )
      let secondPrep = try PdfIncrementalSigner.prepare(
        wiped, revision: .signature(claim)
      )
      return try secondPrep.filled(with: fixture.cms(over: secondPrep, contents))
    }

    /// Prefix collisions, comments, and string literals do not shadow real
    /// dictionary keys.
    @Test
    internal func dictionaryLookupsIgnorePrefixCollisionsAndStrings() throws {
      let trailer =
        "<< /Note (fake >> /Prev 999999 /Encrypt 8 0 R)"
        + " /Preview 777777 /Prev \(Self.realPrevOffset)"
        + " /RootCause 99 0 R /Root \(Self.realRootObject) 0 R"
        + " /Length2 5000 /Length \(Self.realLength)"
        + " /Watermark [9 9 9] /W [1 4 2] >>"

      #expect(
        PdfDocumentIndex.integer(named: "/Prev", in: trailer)
          == Self.realPrevOffset
      )
      #expect(
        PdfDocumentIndex.reference(named: "/Root", in: trailer)
          == Self.realRootObject
      )
      #expect(
        PdfDocumentIndex.integer(named: "/Length", in: trailer)
          == Self.realLength
      )
      #expect(
        PdfDocumentIndex.integerArray(named: "/W", in: trailer).count
          == Self.expectedWidthCount
      )

      let pdfBytes = PdfBytes(Data(("trailer\n" + trailer + "\n").utf8))
      let balanced = try #require(
        pdfBytes.balancedDictionary(from: "trailer\n".utf8.count)
      )
      #expect(balanced.text == trailer)
    }

    /// `/Encrypt` in an older trailer is still refused when a newer
    /// incremental trailer omits `/Encrypt`.
    @Test
    internal func encryptionInOlderRevisionIsRefused() {
      var text = "%PDF-1.7\n"
      let obj1 = text.utf8.count
      text += "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
      let obj2 = text.utf8.count
      text += "2 0 obj\n<< /Type /Pages /Kids [] /Count 0 >>\nendobj\n"
      let xref1 = text.utf8.count
      text += "xref\n0 3\n0000000000 65535 f \n"
      text += String(format: "%010d 00000 n \n", obj1)
      text += String(format: "%010d 00000 n \n", obj2)
      text += "trailer\n<< /Size 3 /Root 1 0 R /Encrypt 9 0 R >>\n"
      text += "startxref\n\(xref1)\n%%EOF\n"
      let xref2 = text.utf8.count
      text += "xref\n0 1\n0000000000 65535 f \n"
      text += "trailer\n<< /Size 3 /Root 1 0 R /Prev \(xref1) >>\n"
      text += "startxref\n\(xref2)\n%%EOF\n"

      #expect(throws: PdfSigningError.encrypted) {
        try PdfDocumentIndex.parse(Data(text.utf8))
      }
    }

    /// Self-referential `/Prev` cycles and out-of-range `/Prev` offsets
    /// fail closed instead of truncating the revision chain.
    @Test
    internal func prevCycleAndOutOfRangeOffsetFailClosed() {
      var cycle = "%PDF-1.7\n"
      let obj1 = cycle.utf8.count
      cycle += "1 0 obj\n<< /Type /Catalog >>\nendobj\n"
      let xref = cycle.utf8.count
      cycle += "xref\n0 2\n0000000000 65535 f \n"
      cycle += String(format: "%010d 00000 n \n", obj1)
      cycle += "trailer\n<< /Size 2 /Root 1 0 R /Prev \(xref) >>\n"
      cycle += "startxref\n\(xref)\n%%EOF\n"

      #expect(throws: PdfSigningError.structureUnreadable) {
        try PdfDocumentIndex.parse(Data(cycle.utf8))
      }

      let outOfBounds = cycle.replacingOccurrences(
        of: "/Prev \(xref)",
        with: "/Prev 999999"
      )
      #expect(throws: PdfSigningError.structureUnreadable) {
        try PdfDocumentIndex.parse(Data(outOfBounds.utf8))
      }
    }

    /// Oversized classic `xref` subsection counts fail immediately.
    @Test
    internal func oversizedCrossReferenceSubsectionFailsImmediately() {
      let huge =
        "%PDF-1.7\n"
        + "xref\n0 999999999999\n"
        + "trailer\n<< /Size 1 /Root 1 0 R >>\n"
        + "startxref\n9\n%%EOF\n"

      #expect(throws: PdfSigningError.structureUnreadable) {
        try PdfDocumentIndex.parse(Data(huge.utf8))
      }
    }

    /// Direct object reads verify that the indirect header at the offset
    /// matches the requested `(number, generation)`.
    @Test
    internal func mismatchedIndirectObjectHeaderReturnsNil() throws {
      var text = "%PDF-1.7\n"
      let wrongOffset = text.utf8.count
      text +=
        "\(Self.mismatchedObjectNumber) 0 obj\n"
        + "<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
      let xref = text.utf8.count
      text += "xref\n0 2\n0000000000 65535 f \n"
      text += String(format: "%010d 00000 n \n", wrongOffset)
      text += "trailer\n<< /Size 2 /Root 1 0 R >>\n"
      text += "startxref\n\(xref)\n%%EOF\n"

      let data = Data(text.utf8)
      let index = try PdfDocumentIndex.parse(data)
      #expect(index.body(of: 1, in: data) == nil)
      #expect(index.comparisonBody(of: 1, in: data) == nil)
    }

    /// Overwriting an earlier signature's object number in a later
    /// revision neither hides the earlier signature nor lets the document
    /// pass verification.
    @Test
    internal func overwrittenEarlierSignatureRemainsVisibleAndFailsDocument() throws {
      let fixture = try DocumentTrustFixture()
      let twiceSigned = try Self.overwrittenSignatureDocument(fixture)

      let located = try PdfSignatureReader.signatures(in: twiceSigned)
      #expect(located.count == Self.twoSignatures)

      let report = try DocumentVerification.verify(
        document: twiceSigned,
        anchors: fixture.anchors(anchorsAuthority: true),
        now: DocumentTrustFixture.instant(Self.currentTime)
      )
      #expect(report.signatures.count == Self.twoSignatures)
      #expect(!report.isValid)
    }

    /// `/Name` tokens spelling PDF keywords such as `/endobj` or `/stream`
    /// inside an object dictionary do not truncate object extraction.
    @Test
    internal func nameTokensMatchingKeywordsDoNotTruncateDirectBody() throws {
      let expectedBody = "<< /Type /Catalog /Tag /endobj /Kind /stream >>"
      var text = "%PDF-1.7\n"
      let objOffset = text.utf8.count
      text += "1 0 obj\n\(expectedBody)\nendobj\n"
      let xref = text.utf8.count
      text += "xref\n0 2\n0000000000 65535 f \n"
      text += String(format: "%010d 00000 n \n", objOffset)
      text += "trailer\n<< /Size 2 /Root 1 0 R >>\n"
      text += "startxref\n\(xref)\n%%EOF\n"

      let data = Data(text.utf8)
      let index = try PdfDocumentIndex.parse(data)
      #expect(index.body(of: 1, in: data) == expectedBody)
      #expect(index.comparisonBody(of: 1, in: data) == expectedBody)
    }

    /// Oversized PNG predictor `/Columns` values fail closed without
    /// arithmetic overflow or huge allocations.
    @Test
    internal func pngPredictorOverflowColumnsFailsClosed() {
      let payload = Data(Self.emptyZlibBytes)
      let head =
        "1 0 obj\n<< /Filter /FlateDecode /Length \(payload.count)"
        + " /DecodeParms << /Predictor \(Self.pngUpPredictor)"
        + " /Columns \(Int.max) >> >>\nstream\n"
      var raw = Data(head.utf8)
      raw.append(payload)
      raw.append(Data("\nendstream\nendobj\n".utf8))

      #expect(throws: PdfSigningError.structureUnreadable) {
        try PdfStreamObject.parse(in: PdfBytes(raw), at: 0)
      }

      let nonEmpty =
        "1 0 obj\n<< /Length 2 /DecodeParms << /Predictor \(Self.pngUpPredictor)"
        + " /Columns \(Int.max - 1) >> >>\nstream\nAB\nendstream\nendobj\n"
      #expect(throws: PdfSigningError.structureUnreadable) {
        try PdfStreamObject.parse(in: PdfBytes(Data(nonEmpty.utf8)), at: 0)
      }
    }
  }

#endif
