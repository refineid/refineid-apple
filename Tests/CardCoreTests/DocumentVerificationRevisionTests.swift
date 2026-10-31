// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// A revision appended after a signature is reported, not judged
  /// (ISO 32000-1 clause 7.5.6).
  @Suite
  internal struct DocumentVerificationRevisionTests {
    /// Inside every certificate's validity.
    private static let currentTime = "20260601000000Z"

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
      #expect(after.isValid == before.isValid)
    }
  }

#endif
