// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// A revision appended after a signature is reported, and only the
  /// material signing and validation may add leaves the signature valid
  /// (ISO 32000-1 clause 12.8.2.2).
  @Suite
  internal struct DocumentVerificationRevisionTests {
    /// Inside every certificate's validity.
    private static let currentTime = "20260601000000Z"

    /// Appends one revision redefining `number` with `body`.
    private static func revision(
      redefining number: Int,
      with body: String,
      in document: Data
    ) throws -> Data {
      let index = try PdfDocumentIndex.parse(document)
      let root = try #require(PdfDocumentIndex.reference(named: "/Root", in: index.trailer))
      let size = try #require(PdfDocumentIndex.integer(named: "/Size", in: index.trailer))
      var out = document
      if out.last != UInt8(ascii: "\n") {
        out.append(UInt8(ascii: "\n"))
      }
      let offset = out.count
      out.append(Data("\(number) 0 obj\n".utf8))
      out.append(Data(body.utf8))
      out.append(Data("\nendobj\n".utf8))
      let xrefOffset = out.count
      out.append(
        try PdfIncrementalSigner.crossReferenceSection(
          offsets: [number: offset],
          size: max(size, number + 1),
          rootNumber: root,
          xrefOffset: xrefOffset,
          index: index
        )
      )
      return out
    }

    /// One object's bytes, as the revision comparison reads them.
    private static func objectBody(_ number: Int, in document: Data) -> String? {
      (try? PdfDocumentIndex.parse(document))?.comparisonBody(of: number, in: document)
    }

    /// The number of the fixture's one page object.
    private static func pageNumber(in document: Data) throws -> Int {
      let index = try PdfDocumentIndex.parse(document)
      let page = index.locations.keys.sorted().first { number in
        index.body(of: number, in: document)?.contains("/Type /Page") == true
      }
      return try #require(page)
    }

    @Test
    internal func unsignedRevisionAfterTheSignatureLeavesItIntact() throws {
      let fixture = try DocumentTrustFixture()
      let signed = try fixture.document(.init(cmsCertificates: [fixture.issuing]))
      let appended = try PdfValidationStore.appended(
        to: signed,
        material: PdfValidationStore.Material(
          certificates: [fixture.root], ocspResponses: [], revocationLists: [])
      )
      try #require(appended.count > signed.count)
      let now = try DocumentTrustFixture.instant(Self.currentTime)
      let anchors = fixture.anchors(anchorsAuthority: true)

      let before = try DocumentTrustFixture.report(signed, anchors: anchors, now: now)
      let after = try DocumentTrustFixture.report(appended, anchors: anchors, now: now)

      #expect(before.coversWholeDocument)
      #expect(!after.coversWholeDocument)
      #expect(after.documentIntact)
      #expect(after.signatureValid)
      #expect(after.changesAfterSigning.isEmpty)
      #expect(after.isValid == before.isValid)
    }

    /// A revision that rewrites a page changes what the signature stands
    /// for, so the verdict is not valid even though the signed bytes are
    /// intact and the signature verifies.
    @Test
    internal func aPageRewrittenAfterSigningMakesTheSignatureInvalid() throws {
      let fixture = try DocumentTrustFixture()
      let signed = try fixture.document(.init(cmsCertificates: [fixture.issuing]))
      let page = try Self.pageNumber(in: signed)
      let rewritten = try Self.revision(
        redefining: page,
        with: "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200]"
          + " /Resources << >> /Contents 9 0 R >>",
        in: signed
      )
      let now = try DocumentTrustFixture.instant(Self.currentTime)
      let anchors = fixture.anchors(anchorsAuthority: true)

      let before = try DocumentTrustFixture.report(signed, anchors: anchors, now: now)
      let after = try DocumentTrustFixture.report(rewritten, anchors: anchors, now: now)

      #expect(before.isValid)
      #expect(after.documentIntact)
      #expect(after.signatureValid)
      #expect(after.coversWholeDocument == false)
      #expect(after.changesAfterSigning == [.pageContent])
      #expect(!after.isValid)
    }

    /// An annotation draws over the page, so one added after signing
    /// changes what the signature stands for.
    @Test
    internal func anAnnotationAddedAfterSigningIsAChange() throws {
      let fixture = try DocumentTrustFixture()
      let signed = try fixture.document(.init(cmsCertificates: [fixture.issuing]))
      let page = try Self.pageNumber(in: signed)
      let index = try PdfDocumentIndex.parse(signed)
      let pageBody = try #require(index.body(of: page, in: signed))
      let size = try #require(PdfDocumentIndex.integer(named: "/Size", in: index.trailer))
      try #require(pageBody.hasSuffix(">>"))
      let stamped = try Self.revision(
        redefining: size,
        with: "<< /Type /Annot /Subtype /Text /Rect [0 0 200 50] /Contents (Approved) >>",
        in: signed
      )
      let annotated = try Self.revision(
        redefining: page,
        with: String(pageBody.dropLast(2)) + " /Annots [\(size) 0 R] >>",
        in: stamped
      )
      let now = try DocumentTrustFixture.instant(Self.currentTime)
      let anchors = fixture.anchors(anchorsAuthority: true)

      let after = try DocumentTrustFixture.report(annotated, anchors: anchors, now: now)

      #expect(after.changesAfterSigning.contains(.pageContent))
      #expect(!after.isValid)
    }

    /// A stream's dictionary can stay the same while what it draws
    /// changes, so a rewritten payload is a change of its own.
    @Test
    internal func aStreamRewrittenUnderTheSameDictionaryIsAChange() throws {
      let number = 4
      let signed = StorePdf.document(
        catalog: StorePdf.catalog(),
        extraObjects: [number: StorePdf.stream("q 1 0 0 1 0 0 cm Q")]
      )
      let rewritten = try Self.revision(
        redefining: number,
        with: StorePdf.stream("q 1 0 0 1 0 0 cm R"),
        in: signed
      )

      let changes = PdfSignedContentAnalysis.changes(
        document: rewritten,
        signedEnd: signed.count
      )

      #expect(changes == [.object(number)])
    }

    /// A widget that borrows the signature already in the file could
    /// carry any appearance over the signed page, so it is a change.
    @Test
    internal func aWidgetWearingTheOriginalSignatureIsAPageChange() throws {
      let fixture = try DocumentTrustFixture()
      let signed = try fixture.document(.init(cmsCertificates: [fixture.issuing]))
      let index = try PdfDocumentIndex.parse(signed)
      let page = try Self.pageNumber(in: signed)
      let pageBody = try #require(Self.objectBody(page, in: signed))
      let signature = try #require(
        index.locations.keys.sorted().first { number in
          Self.objectBody(number, in: signed)?.contains("/ByteRange") == true
        })
      let size = try #require(PdfDocumentIndex.integer(named: "/Size", in: index.trailer))
      try #require(pageBody.hasSuffix(">>"))
      let widget = try Self.revision(
        redefining: size,
        with: "<< /Type /Annot /Subtype /Widget /FT /Sig /V \(signature) 0 R"
          + " /Rect [0 0 200 200] /F 4 >>",
        in: signed
      )
      let annotated = try Self.revision(
        redefining: page,
        with: String(pageBody.dropLast(2)) + " /Annots [\(size) 0 R] >>",
        in: widget
      )
      let now = try DocumentTrustFixture.instant(Self.currentTime)
      let anchors = fixture.anchors(anchorsAuthority: true)

      let after = try DocumentTrustFixture.report(annotated, anchors: anchors, now: now)

      #expect(after.changesAfterSigning.contains(.pageContent))
      #expect(!after.isValid)
    }

    /// A new page object is not what signing may add, whatever it draws.
    @Test
    internal func aPageAddedAfterSigningIsAChange() throws {
      let fixture = try DocumentTrustFixture()
      let signed = try fixture.document(.init(cmsCertificates: [fixture.issuing]))
      let index = try PdfDocumentIndex.parse(signed)
      let size = try #require(PdfDocumentIndex.integer(named: "/Size", in: index.trailer))
      let added = try Self.revision(
        redefining: size,
        with: "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> >>",
        in: signed
      )
      let now = try DocumentTrustFixture.instant(Self.currentTime)
      let anchors = fixture.anchors(anchorsAuthority: true)

      let after = try DocumentTrustFixture.report(added, anchors: anchors, now: now)

      #expect(after.changesAfterSigning == [.object(size)])
      #expect(!after.isValid)
    }
  }

#endif
