// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// Regression tests for post-signature PDF incremental update rules:
  /// widget appearance locking, 1-to-1 signature binding, `DocTimeStamp`
  /// invisibility, `#xx` name escapes, and scoped additions.
  @Suite
  internal struct DocumentVerificationHardeningTests {
    /// Inside every synthetic certificate's validity window.
    internal static let currentTime = "20260601000000Z"

    /// Document timestamp generation time.
    internal static let stampTime = "20260520000000Z"

    /// Trailing `>>` marker length of a PDF dictionary.
    private static let closingMarkerLength = 2

    /// Expected signature row count after counter-signing.
    internal static let twoSignatures = 2

    /// Appends one incremental revision redefining `objects` in `document`.
    internal static func revision(
      redefining objects: [Int: String],
      in document: Data
    ) throws -> Data {
      let index = try PdfDocumentIndex.parse(document)
      let root = try #require(
        PdfDocumentIndex.reference(named: "/Root", in: index.trailer)
      )
      let size = try #require(
        PdfDocumentIndex.integer(named: "/Size", in: index.trailer)
      )
      var out = document
      if out.last != UInt8(ascii: "\n") {
        out.append(UInt8(ascii: "\n"))
      }
      var offsets: [Int: Int] = [:]
      var nextSize = size
      for number in objects.keys.sorted() {
        guard let body = objects[number] else { continue }
        offsets[number] = out.count
        out.append(Data("\(number) 0 obj\n\(body)\nendobj\n".utf8))
        nextSize = max(nextSize, number + 1)
      }
      let xrefOffset = out.count
      out.append(
        try PdfIncrementalSigner.crossReferenceSection(
          offsets: offsets,
          size: nextSize,
          rootNumber: root,
          xrefOffset: xrefOffset,
          index: index
        )
      )
      return out
    }

    /// Finds the sole `/Page` object number in `document`.
    internal static func pageNumber(in document: Data) throws -> Int {
      let index = try PdfDocumentIndex.parse(document)
      let found = index.locations.keys.sorted().first { number in
        index.body(of: number, in: document).map { body in
          PdfTypeEntry.value(of: "Type", in: body) == "/Page"
        } == true
      }
      return try #require(found)
    }

    /// Finds the first `/Subtype /Widget` object number in `document`.
    private static func widgetNumber(in document: Data) throws -> Int {
      let index = try PdfDocumentIndex.parse(document)
      let found = index.locations.keys.sorted().first { number in
        index.body(of: number, in: document).map { body in
          PdfTypeEntry.value(of: "Subtype", in: body) == "/Widget"
        } == true
      }
      return try #require(found)
    }

    /// A cryptographically verified visible counter-signature keeps the
    /// earlier signature valid.
    @Test
    internal func verifiedVisibleCounterSignatureLeavesFirstSignatureValid() throws {
      let fixture = try DocumentTrustFixture()
      let contents = DocumentTrustFixture.Contents(
        cmsCertificates: [fixture.issuing]
      )
      let first = try fixture.document(contents)
      let mark = PdfStampRenderer.stampMark(locale: Locale(identifier: "en_US"))
      let claim = PdfIncrementalSigner.SignatureClaim(
        signedAt: Date(timeIntervalSince1970: 0), reason: nil, location: nil
      )
      let prepared = try PdfIncrementalSigner.prepare(
        first, revision: .signature(claim), appending: mark
      )
      let twiceSigned = try prepared.filled(
        with: fixture.cms(over: prepared, contents)
      )
      let report = try DocumentVerification.verify(
        document: twiceSigned,
        anchors: fixture.anchors(anchorsAuthority: true),
        now: DocumentTrustFixture.instant(Self.currentTime)
      )
      try #require(report.signatures.count == Self.twoSignatures)
      #expect(report.isValid)
    }

    /// Rewriting `/AP` on an already-signed widget without touching `/V`
    /// invalidates the signature.
    @Test
    internal func rewritingAppearanceOnSignedWidgetInvalidatesSignature() throws {
      let fixture = try DocumentTrustFixture()
      let signed = try fixture.document(
        .init(cmsCertificates: [fixture.issuing])
      )
      let index = try PdfDocumentIndex.parse(signed)
      let widget = try Self.widgetNumber(in: signed)
      let widgetBody = try #require(index.body(of: widget, in: signed))
      let size = try #require(
        PdfDocumentIndex.integer(named: "/Size", in: index.trailer)
      )
      let streamBody =
        "<< /Type /XObject /Subtype /Form /BBox [0 0 100 100] /Length 4 >>\n"
        + "stream\nq Q\nendstream"
      let updatedWidget =
        String(widgetBody.dropLast(Self.closingMarkerLength))
        + " /AP << /N \(size) 0 R >> >>"
      let tampered = try Self.revision(
        redefining: [widget: updatedWidget, size: streamBody],
        in: signed
      )
      let after = try DocumentTrustFixture.report(
        tampered,
        anchors: fixture.anchors(anchorsAuthority: true),
        now: DocumentTrustFixture.instant(Self.currentTime)
      )
      #expect(after.changesAfterSigning.contains(.pageContent))
      #expect(!after.isValid)
    }

    /// A `/ByteRange`-only stub dictionary cannot authorize a new widget
    /// on a signed page.
    @Test
    internal func stubByteRangeDictionaryCannotAuthorizeWidget() throws {
      let fixture = try DocumentTrustFixture()
      let signed = try fixture.document(
        .init(cmsCertificates: [fixture.issuing])
      )
      let index = try PdfDocumentIndex.parse(signed)
      let page = try Self.pageNumber(in: signed)
      let pageBody = try #require(index.body(of: page, in: signed))
      let size = try #require(
        PdfDocumentIndex.integer(named: "/Size", in: index.trailer)
      )
      let fakeSig = size
      let fakeWidget = size + 1
      let updatedPage = PdfIncrementalSigner.appendingToNamedArray(
        pageBody, key: "/Annots", entry: fakeWidget
      )
      let tampered = try Self.revision(
        redefining: [
          page: updatedPage,
          fakeSig: "<< /Type /Sig /ByteRange [0 1 2 3] >>",
          fakeWidget:
            "<< /Type /Annot /Subtype /Widget /FT /Sig"
            + " /V \(fakeSig) 0 R /Rect [10 10 80 40] >>",
        ],
        in: signed
      )
      let after = try DocumentTrustFixture.report(
        tampered,
        anchors: fixture.anchors(anchorsAuthority: true),
        now: DocumentTrustFixture.instant(Self.currentTime)
      )
      #expect(after.changesAfterSigning.contains(.pageContent))
      #expect(!after.isValid)
    }

    /// `"stream"` inside a string literal and `#xx` hex escapes in `/Type`
    /// cannot disguise rewritten or added objects.
    @Test
    internal func stringStreamWordAndHexEscapedNamesDoNotBypassChecks() throws {
      let fixture = try DocumentTrustFixture()
      let signed = try fixture.document(
        .init(cmsCertificates: [fixture.issuing])
      )
      let page = try Self.pageNumber(in: signed)
      let disguisedPage = try Self.revision(
        redefining: [
          page:
            "<< /Note (stream) /Type /#50age /Parent 2 0 R"
            + " /MediaBox [0 0 200 200] >>"
        ],
        in: signed
      )
      let anchors = fixture.anchors(anchorsAuthority: true)
      let now = try DocumentTrustFixture.instant(Self.currentTime)
      let pageReport = try DocumentTrustFixture.report(
        disguisedPage, anchors: anchors, now: now
      )
      #expect(pageReport.changesAfterSigning.contains(.pageContent))
      #expect(!pageReport.isValid)

      let index = try PdfDocumentIndex.parse(signed)
      let size = try #require(
        PdfDocumentIndex.integer(named: "/Size", in: index.trailer)
      )
      let unreferencedStream = try Self.revision(
        redefining: [size: StorePdf.stream("q 1 0 0 1 0 0 cm Q")],
        in: signed
      )
      let streamReport = try DocumentTrustFixture.report(
        unreferencedStream, anchors: anchors, now: now
      )
      #expect(streamReport.changesAfterSigning == [.object(size)])
      #expect(!streamReport.isValid)
    }
  }

#endif
