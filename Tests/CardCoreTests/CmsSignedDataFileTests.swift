// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// A CMS SignedData file is recognised as a signature format this
  /// verifier does not verify, never as an unsigned document.
  @Suite
  internal struct CmsSignedDataFileTests {
    /// Text that is no DER at all.
    private static let notDer = Data("not a signature".utf8)

    @Test
    internal func aSignedDataIsRecognisedAndRefusedAsCades() throws {
      let fixture = try DocumentTrustFixture()
      let cms = try fixture.cms(over: QualifiedDocumentCmsTests.placeholder(), .init())

      #expect(CmsSignedDataFile.isSignedData(cms))
      #expect(throws: DocumentVerification.Failure.cmsSignedData) {
        try DocumentVerification.verify(document: cms, anchors: .empty)
      }
    }

    @Test
    internal func otherContentIsNoSignedData() {
      let otherContentInfo = DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.data)])

      #expect(!CmsSignedDataFile.isSignedData(Self.notDer))
      #expect(!CmsSignedDataFile.isSignedData(otherContentInfo))
      #expect(!CmsSignedDataFile.isSignedData(PdfIncrementalSignerTests.minimalPdf))
    }
  }

#endif
