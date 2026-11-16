// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// Geometry bounds, `DocTimeStamp` invisibility, and `DocMDP` `/P 1`
  /// certification tests for `DocumentVerificationHardeningTests`.
  extension DocumentVerificationHardeningTests {
    /// Placeholder character count for in-place `/Reference` patching.
    private static let reasonPaddingCount = 140

    /// Object number of the synthetic `/DCTDecode` image stream.
    private static let dctStreamObjectNumber = 4

    /// Minimal synthetic `/DCTDecode` stream bytes.
    private static let jpegStubText = "JPEG"

    /// Altered `/DCTDecode` stream bytes for rewrite detection.
    private static let tamperedJpegText = "JPE!"

    /// Minimal PDF carrying an indirect `/Filter /DCTDecode` image stream.
    private static var minimalPdfWithDctStream: Data {
      let jpegStub = Data(Self.jpegStubText.utf8)
      var out = Data("%PDF-1.7\n".utf8)
      let obj1 = out.count
      out.append(Data("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n".utf8))
      let obj2 = out.count
      out.append(
        Data("2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n".utf8)
      )
      let obj3 = out.count
      out.append(
        Data(
          ("3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792]"
            + " /Resources << /XObject << /Im0 4 0 R >> >> >>\nendobj\n").utf8
        )
      )
      let obj4 = out.count
      out.append(
        Data(
          ("4 0 obj\n<< /Type /XObject /Subtype /Image /Width 1 /Height 1"
            + " /ColorSpace /DeviceGray /BitsPerComponent 8"
            + " /Filter /DCTDecode /Length \(jpegStub.count) >>\nstream\n").utf8
        )
      )
      out.append(jpegStub)
      out.append(Data("\nendstream\nendobj\n".utf8))
      let xref = out.count
      var trailer = "xref\n0 5\n0000000000 65535 f \n"
      for offset in [obj1, obj2, obj3, obj4] {
        trailer += String(format: "%010d 00000 n \n", offset)
      }
      trailer += "trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
      out.append(Data(trailer.utf8))
      return out
    }

    /// Signs a minimal PDF certified with no-changes `DocMDP` permission.
    private static func certifiedNoChangesDocument(
      _ fixture: DocumentTrustFixture
    ) throws -> Data {
      let claim = PdfIncrementalSigner.SignatureClaim(
        signedAt: Date(timeIntervalSince1970: 0),
        reason: String(repeating: "R", count: Self.reasonPaddingCount),
        location: nil
      )
      let base = try PdfIncrementalSigner.prepare(
        PdfIncrementalSignerTests.minimalPdf,
        revision: .signature(claim)
      )
      let text = try #require(
        String(bytes: base.document, encoding: .isoLatin1)
      )
      let reasonStart = try #require(text.range(of: "/Reason "))
      let reasonEnd = try #require(
        text[reasonStart.lowerBound...].firstIndex(of: "\n")
      )
      let oldLine = String(text[reasonStart.lowerBound..<reasonEnd])
      let docMdpLine =
        "/Reference [ << /Type /SigRef /TransformMethod /DocMDP"
        + " /TransformParams << /Type /TransformParams /P 1 /V /1.2 >> >> ]"
      try #require(docMdpLine.utf8.count <= oldLine.utf8.count)
      let paddedLine =
        docMdpLine
        + String(repeating: " ", count: oldLine.utf8.count - docMdpLine.utf8.count)
      let updatedText = text.replacingOccurrences(of: oldLine, with: paddedLine)
      let updatedBytes = try #require(updatedText.data(using: .isoLatin1))
      try #require(updatedBytes.count == base.document.count)
      let patched = PdfSignaturePlaceholder(
        document: updatedBytes,
        contentsOpen: base.contentsOpen,
        secondSpanStart: base.secondSpanStart,
        capacity: base.capacity
      )
      let contents = DocumentTrustFixture.Contents(
        cmsCertificates: [fixture.issuing]
      )
      return try patched.filled(with: fixture.cms(over: patched, contents))
    }

    /// Appends an incremental revision that rewrites object 4's `/DCTDecode`
    /// stream payload.
    private static func tamperedDctDocument(_ base: Data) throws -> Data {
      let index = try PdfDocumentIndex.parse(base)
      let root = try #require(
        PdfDocumentIndex.reference(named: "/Root", in: index.trailer)
      )
      let size = try #require(
        PdfDocumentIndex.integer(named: "/Size", in: index.trailer)
      )
      var tampered = base
      let newOffset = tampered.count
      let replacement = Data(Self.tamperedJpegText.utf8)
      tampered.append(
        Data(
          ("4 0 obj\n<< /Type /XObject /Subtype /Image /Width 1 /Height 1"
            + " /ColorSpace /DeviceGray /BitsPerComponent 8"
            + " /Filter /DCTDecode /Length \(replacement.count) >>\nstream\n").utf8
        )
      )
      tampered.append(replacement)
      tampered.append(Data("\nendstream\nendobj\n".utf8))
      let xrefOffset = tampered.count
      tampered.append(
        try PdfIncrementalSigner.crossReferenceSection(
          offsets: [Self.dctStreamObjectNumber: newOffset],
          size: size,
          rootNumber: root,
          xrefOffset: xrefOffset,
          index: index
        )
      )
      return tampered
    }

    /// A visible counter-signature widget covering the full page invalidates
    /// the earlier signature even when the second CMS verifies.
    @Test
    internal func fullPageCounterSignatureWidgetInvalidatesFirstSignature() throws {
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
      let updateSlice = prepared.document.dropFirst(first.count)
      let updateText = try #require(
        String(bytes: updateSlice, encoding: .isoLatin1)
      )
      let rectRange = try #require(updateText.range(of: "/Rect ["))
      let closeBracket = try #require(
        updateText[rectRange.upperBound...].firstIndex(of: "]")
      )
      let oldRect = String(updateText[rectRange.upperBound..<closeBracket])
      let fullRect = "0 0 612 792"
      let paddedRect =
        fullRect
        + String(repeating: " ", count: max(0, oldRect.count - fullRect.count))
      let patchedUpdate = updateText.replacingOccurrences(
        of: "/Rect [" + oldRect + "]",
        with: "/Rect [" + paddedRect + "]"
      )
      let repatched = PdfSignaturePlaceholder(
        document: first + Data(patchedUpdate.utf8),
        contentsOpen: prepared.contentsOpen,
        secondSpanStart: prepared.secondSpanStart,
        capacity: prepared.capacity
      )
      let twiceSigned = try repatched.filled(
        with: fixture.cms(over: repatched, contents)
      )
      let report = try DocumentVerification.verify(
        document: twiceSigned,
        anchors: fixture.anchors(anchorsAuthority: true),
        now: DocumentTrustFixture.instant(Self.currentTime)
      )
      try #require(report.signatures.count == Self.twoSignatures)
      guard case .judged(let earlier) = report.signatures[0] else {
        Issue.record("First signature was not judged")
        return
      }
      #expect(earlier.changesAfterSigning.contains(.pageContent))
      #expect(!earlier.isValid)
    }

    /// A `DocTimeStamp` widget carrying a non-zero `/Rect` is flagged as
    /// a page modification.
    @Test
    internal func visibleDocumentTimestampWidgetInvalidatesSignature() throws {
      let fixture = try DocumentTrustFixture()
      let signed = try fixture.document(
        .init(cmsCertificates: [fixture.issuing])
      )
      let prepared = try PdfIncrementalSigner.prepare(
        signed, revision: .documentTimestamp
      )
      let head = prepared.document.prefix(signed.count)
      let tail = try #require(
        String(
          bytes: prepared.document.dropFirst(signed.count),
          encoding: .isoLatin1
        )
      )
      let patchedTail = tail.replacingOccurrences(
        of: "/Rect [0 0 0 0]",
        with: "/Rect [0 0 9 9]"
      )
      let repatched = PdfSignaturePlaceholder(
        document: head + Data(patchedTail.utf8),
        contentsOpen: prepared.contentsOpen,
        secondSpanStart: prepared.secondSpanStart,
        capacity: prepared.capacity
      )
      let token = try fixture.authority.token(
        imprint: repatched.digest(.sha384),
        generalizedTime: Self.stampTime
      )
      let stamped = try repatched.filled(with: token)
      let after = try DocumentTrustFixture.report(
        stamped,
        anchors: fixture.anchors(anchorsAuthority: true),
        now: DocumentTrustFixture.instant(Self.currentTime)
      )
      #expect(after.changesAfterSigning.contains(.pageContent))
      #expect(!after.isValid)
    }

    /// `DocMDP` `/P 1` permits LTV `DSS` + `DocTimeStamp` revisions and
    /// rejects post-certification counter-signatures.
    @Test
    internal func docMdpNoChangesPermitsTimestampAndRejectsCounterSignature() throws {
      let fixture = try DocumentTrustFixture()
      let certified = try Self.certifiedNoChangesDocument(fixture)
      let withStore = try PdfValidationStore.appended(
        to: certified,
        material: PdfValidationStore.Material(
          certificates: [fixture.root], ocspResponses: [], revocationLists: []
        )
      )
      let stampPrep = try PdfIncrementalSigner.prepare(
        withStore, revision: .documentTimestamp
      )
      let token = try fixture.authority.token(
        imprint: stampPrep.digest(.sha384),
        generalizedTime: Self.stampTime
      )
      let ltvDocument = try stampPrep.filled(with: token)
      let anchors = fixture.anchors(anchorsAuthority: true)
      let now = try DocumentTrustFixture.instant(Self.currentTime)
      let ltvReport = try DocumentTrustFixture.report(
        ltvDocument, anchors: anchors, now: now
      )
      #expect(ltvReport.isValid)

      let claim = PdfIncrementalSigner.SignatureClaim(
        signedAt: Date(timeIntervalSince1970: 0), reason: nil, location: nil
      )
      let counterPrep = try PdfIncrementalSigner.prepare(
        certified, revision: .signature(claim)
      )
      let contents = DocumentTrustFixture.Contents(
        cmsCertificates: [fixture.issuing]
      )
      let counterSigned = try counterPrep.filled(
        with: fixture.cms(over: counterPrep, contents)
      )
      let counterReport = try DocumentVerification.verify(
        document: counterSigned, anchors: anchors, now: now
      )
      try #require(counterReport.signatures.count == Self.twoSignatures)
      guard case .judged(let certRow) = counterReport.signatures[0] else {
        Issue.record("Certified signature was not judged")
        return
      }
      #expect(!certRow.changesAfterSigning.isEmpty)
      #expect(!certRow.isValid)
      #expect(!counterReport.isValid)
    }

    /// Unchanged non-Flate (`/DCTDecode`) streams remain valid across
    /// `DocTimeStamp` revisions, while rewriting their bytes is detected.
    @Test
    internal func nonFlateImageStreamStaysValidUntilModified() throws {
      let fixture = try DocumentTrustFixture()
      let contents = DocumentTrustFixture.Contents(
        cmsCertificates: [fixture.issuing]
      )
      let claim = PdfIncrementalSigner.SignatureClaim(
        signedAt: Date(timeIntervalSince1970: 0), reason: nil, location: nil
      )
      let prepared = try PdfIncrementalSigner.prepare(
        Self.minimalPdfWithDctStream, revision: .signature(claim)
      )
      let signed = try prepared.filled(with: fixture.cms(over: prepared, contents))
      let stampPrep = try PdfIncrementalSigner.prepare(
        signed, revision: .documentTimestamp
      )
      let token = try fixture.authority.token(
        imprint: stampPrep.digest(.sha384), generalizedTime: Self.stampTime
      )
      let stamped = try stampPrep.filled(with: token)
      let anchors = fixture.anchors(anchorsAuthority: true)
      let now = try DocumentTrustFixture.instant(Self.currentTime)
      let cleanReport = try DocumentTrustFixture.report(
        stamped, anchors: anchors, now: now
      )
      #expect(cleanReport.changesAfterSigning.isEmpty)
      #expect(cleanReport.isValid)

      let tampered = try Self.tamperedDctDocument(stamped)
      let tamperedReport = try DocumentTrustFixture.report(
        tampered, anchors: anchors, now: now
      )
      #expect(
        tamperedReport.changesAfterSigning.contains(
          .object(Self.dctStreamObjectNumber)
        )
      )
      #expect(!tamperedReport.isValid)
    }
  }

#endif
