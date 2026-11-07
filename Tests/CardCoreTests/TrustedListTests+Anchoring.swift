// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// Documents judged under the anchors the synthetic lists yield.
  extension TrustedListTests {
    @Test
    internal func aSignerUnderAListedIssuingCaIsAnchored() throws {
      let fixture = try TrustedListFixture()
      let hierarchy = fixture.hierarchy
      let report = try DocumentTrustFixture.report(
        try hierarchy.document(.init(cmsCertificates: [hierarchy.issuing])),
        anchors: try fixture.anchors(),
        now: try DocumentTrustFixture.instant(TrustedListFixture.whileGranted)
      )
      #expect(report.documentIntact)
      #expect(report.signatureValid)
      #expect(report.chainVerified)
      #expect(report.chain == .anchored(path: [hierarchy.signer.certificate, hierarchy.issuing]))
      #expect(report.issuerCertificate == hierarchy.issuing)
      #expect(report.isValid)
    }

    @Test
    internal func aSignerWhoseRootIsCarriedButNotListedEndsAtTheIssuingCa() throws {
      let fixture = try TrustedListFixture()
      let hierarchy = fixture.hierarchy
      let report = try DocumentTrustFixture.report(
        try hierarchy.document(.init(cmsCertificates: [hierarchy.issuing, hierarchy.root])),
        anchors: try fixture.anchors(),
        now: try DocumentTrustFixture.instant(TrustedListFixture.whileGranted)
      )
      #expect(report.chain == .anchored(path: [hierarchy.signer.certificate, hierarchy.issuing]))
    }

    @Test
    internal func nothingAnchorsBeforeTheServiceWasGranted() throws {
      let fixture = try TrustedListFixture()
      let hierarchy = fixture.hierarchy
      let beforeGrant = try TrustedListFixture.instant(TrustedListFixture.supervised)
        .addingTimeInterval(-1)
      let report = try DocumentTrustFixture.report(
        try hierarchy.document(.init(cmsCertificates: [hierarchy.issuing])),
        anchors: try fixture.anchors(),
        now: beforeGrant
      )
      #expect(!report.chainVerified)
    }

    @Test
    internal func aWithdrawnTimeStampingServiceAnchorsOnlyUntilItsWithdrawal() throws {
      let fixture = try TrustedListFixture()
      let hierarchy = fixture.hierarchy
      let anchors = try fixture.anchors()
      let now = try DocumentTrustFixture.instant(TrustedListFixture.afterWithdrawal)
      let whileGranted = try DocumentTrustFixture.report(
        try hierarchy.document(
          .init(
            cmsCertificates: [hierarchy.issuing],
            timestampTimes: [TrustedListFixture.whileGranted])),
        anchors: anchors, now: now)
      let stamped = try DocumentTrustFixture.instant(TrustedListFixture.whileGranted)
      #expect(whileGranted.timestamps == [.anchored(stamped)])
      #expect(whileGranted.proofOfExistence == stamped)

      let afterWithdrawal = try DocumentTrustFixture.report(
        try hierarchy.document(
          .init(
            cmsCertificates: [hierarchy.issuing],
            timestampTimes: [TrustedListFixture.afterWithdrawal])),
        anchors: anchors, now: now)
      #expect(afterWithdrawal.timestamps == [.claimed(now)])
      #expect(afterWithdrawal.proofOfExistence == nil)
    }

    @Test
    internal func emptyAnchorsAnchorNothing() throws {
      let fixture = try TrustedListFixture()
      let hierarchy = fixture.hierarchy
      let report = try DocumentTrustFixture.report(
        try hierarchy.document(.init(cmsCertificates: [hierarchy.issuing, hierarchy.root])),
        anchors: .empty,
        now: try DocumentTrustFixture.instant(TrustedListFixture.whileGranted)
      )
      #expect(report.signatureValid)
      #expect(!report.chainVerified)
      #expect(!report.isValid)
    }
  }

#endif
