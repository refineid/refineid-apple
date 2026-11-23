// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import Foundation
  import Testing

  @testable import CardCore
  @testable import RefineIDTestHost

  /// Signs a PDF and an ASiC-E container through the production stages
  /// that decide their level, against the synthetic authorities, and
  /// exports them for the EU DSS validator (`Scripts/dss-gate.py`).
  ///
  /// The card is the only stand-in: a generated RSA-2048 key signs what
  /// the card would sign. From the card's answer on, the code is the
  /// app's: `TimestampClient`, `DocumentSigner.longTerm` and
  /// `AsicSigner.evidenced`, over the app's own signing network, whose
  /// requests `DssGateUrlProtocol` answers in memory. What level the
  /// files reach is for DSS to say, not this test.
  @Suite(.serialized, DssGateFixtureScope())
  internal final class DssGateExportTests {
    /// Where the files go: the test host's temporary directory, which
    /// `Scripts/dss-gate.py` reads.
    private static var exportDirectory: URL {
      FileManager.default.temporaryDirectory.appending(
        path: "RefineIDDssGate", directoryHint: .isDirectory
      )
    }

    private static let testDigestByteCount = 48
    private static let testDigestPattern: UInt8 = 0x42

    /// Writes `swift-pades.pdf`, `swift-asic-e.asice` and the anchors
    /// DSS is to trust.

    @Test
    internal func testExportsPdfAndAsicSignaturesForDss() async throws {
      try await DssGateSessionHook.withFixture(authorities: DssGateAuthorities.make()) {
        let authorities = try #require(DssGateUrlProtocol.authorities)
        let tsCaCertificate = authorities.timestampCaCertificate
        try await DssGateExportFixture.withSyntheticTimestampEnvironment(
          anchors: { _ in [tsCaCertificate] },
          operation: {
            let directory = Self.exportDirectory
            try? FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(
              at: directory, withIntermediateDirectories: true)
            try authorities.caCertificate.write(to: directory.appending(path: "anchor-ca.der"))
            try authorities.timestampCaCertificate.write(
              to: directory.appending(path: "anchor-tsa.der")
            )
            let pdf = try await DssGateExportFixture.signedPdf(authorities)
            try pdf.write(to: directory.appending(path: "swift-pades.pdf"))
            let container = try await DssGateExportFixture.signedContainer(authorities)
            try container.write(to: directory.appending(path: "swift-asic-e.asice"))
            let intercepted = Set(DssGateUrlProtocol.interceptedAddresses)
            #expect(intercepted.contains(TimestampClient.authority(in: .standard)))
            #expect(intercepted.contains(DssGateAuthorities.revocationListAddress))
            #expect(intercepted.contains(DssGateAuthorities.timestampRevocationListAddress))
            print("DSS gate export: \(directory.path)")
          }
        )

      }
    }

    /// Live token(over:) verifies a signer chained to a separate CA anchor.
    @Test
    internal func testLiveTokenOverAuthenticatesSignerChainedToCaAnchor() async throws {
      try await DssGateSessionHook.withFixture(authorities: DssGateAuthorities.make()) {
        let authorities = try #require(DssGateUrlProtocol.authorities)
        let digest = Data(repeating: Self.testDigestPattern, count: Self.testDigestByteCount)
        let tsCaCertificate = authorities.timestampCaCertificate
        let verified = try await DssGateExportFixture.withSyntheticTimestampEnvironment(
          anchors: { _ in [tsCaCertificate] },
          operation: {
            try await TimestampClient.token(over: digest)
          }
        )
        #expect(
          DssGateUrlProtocol.interceptedAddresses.contains(
            TimestampClient.authority(in: .standard)
          )
        )
        #expect((verified.signerCertificate) == (authorities.timestampAuthority.certificate))
        #expect((verified.trustedCertificate) == (authorities.timestampCaCertificate))
        #expect(
          (verified.verifiedCertificateChain)
            == ([
              authorities.timestampAuthority.certificate,
              authorities.timestampCaCertificate,
            ]))

      }
    }

    /// Live token(over:) rejects a timestamp signer not anchored at the trusted CA.
    @Test
    internal func testLiveTokenOverRejectsSignerNotAnchoredAtCa() async throws {
      try await DssGateSessionHook.withFixture(authorities: DssGateAuthorities.make()) {
        let authorities = try #require(DssGateUrlProtocol.authorities)
        let digest = Data(repeating: Self.testDigestPattern, count: Self.testDigestByteCount)
        let caCertificate = authorities.caCertificate
        do {
          _ = try await DssGateExportFixture.withSyntheticTimestampEnvironment(
            anchors: { _ in [caCertificate] },
            operation: {
              try await TimestampClient.token(over: digest)
            }
          )
          Issue.record("Expected untrustedAuthority failure")
        } catch let error as TimestampClient.Failure {
          guard case .untrustedAuthority = error else {
            Issue.record("Expected .untrustedAuthority but got \(error)")
            return
          }
        } catch {
          Issue.record("Unexpected error: \(error)")
        }

      }
    }

    /// The verifier the Mac's Verify button runs reads both release
    /// signatures as B-LTA under the gate's CA and authority alone, the
    /// archive timestamp anchored after the signature timestamp.
    @Test
    internal func testOwnVerifierReadsBothAtLongTermArchival() async throws {
      try await DssGateSessionHook.withFixture(authorities: DssGateAuthorities.make()) {
        let authorities = try #require(DssGateUrlProtocol.authorities)
        let tsCaCertificate = authorities.timestampCaCertificate
        try await DssGateExportFixture.withSyntheticTimestampEnvironment(
          anchors: { _ in [tsCaCertificate] },
          operation: {
            try await self.assertDocumentsReadAtLongTermArchival(authorities: authorities)
          }
        )

      }
    }

    /// Signing a PDF followed by an ASiC-E container under the 15-second
    /// throttle waits once between the two documents, never between a
    /// document's own signature and archive timestamps, and never on a
    /// Settings probe.
    @Test
    internal func testShippedThrottleSpacesSeparateDocumentsAndExemptsProbes() async throws {
      try await DssGateSessionHook.withFixture(authorities: DssGateAuthorities.make()) {
        let authorities = try #require(DssGateUrlProtocol.authorities)
        let tsCaCertificate = authorities.timestampCaCertificate
        let clock = TimestampThrottleTests.FakeClock(origin: ContinuousClock.now)
        let throttle = TimestampThrottle(
          now: clock.now,
          sleep: { duration in clock.sleep(duration) },
          spacing: TimestampThrottle.minimumDocumentSpacing
        )
        let resolver: @Sendable (Date) -> [Data] = { _ in [tsCaCertificate] }
        try await TimestampClient.$throttle.withValue(throttle) {
          try await TimestampClient.$anchorResolver.withValue(resolver) {
            _ = try await DssGateExportFixture.signedPdf(authorities)
            #expect((clock.sleeps.isEmpty))

            _ = try await DssGateExportFixture.signedContainer(authorities)
            #expect((clock.sleeps) == ([TimestampThrottle.minimumDocumentSpacing]))

            try await TimestampClient.probe(TimestampClient.authority(in: .standard))
            #expect((clock.sleeps) == ([TimestampThrottle.minimumDocumentSpacing]))
          }
        }

      }
    }

    private func assertDocumentsReadAtLongTermArchival(
      authorities: DssGateAuthorities
    ) async throws {
      let anchors = TrustAnchors(
        anchors: [
          TrustAnchor(
            certificate: authorities.caCertificate, role: .certificateIssuing,
            granted: [.unbounded]),
          TrustAnchor(
            certificate: authorities.timestampCaCertificate, role: .timeStamping,
            granted: [.unbounded]),
        ].compactMap(\.self),
        fetchedAt: nil,
        listsValidUntil: nil
      )
      let documents = [
        ("swift-pades.pdf", try await DssGateExportFixture.signedPdf(authorities)),
        ("swift-asic-e.asice", try await DssGateExportFixture.signedContainer(authorities)),
      ]
      for (name, document) in documents {
        let report = try DocumentVerification.verify(document: document, anchors: anchors)
        #expect((report.signatures.count) == (1), "\(name)")
        guard case .judged(let signature) = report.signatures.first else {
          Issue.record("\(name): the signature was not judged")
          continue
        }
        #expect((signature.isValid), "\(name)")
        #expect((signature.chainVerified), "\(name)")
        #expect((signature.level) == (.longTermArchival), "\(name)")
        let validUntil = try #require(signature.archiveValidUntil, "\(name)")
        #expect((validUntil) > (Date()), "\(name)")
        let proof = try #require(signature.proofOfExistence, "\(name)")
        let archive = try #require(
          signature.archiveTimestamps.compactMap(\.provenTime).max(), "\(name)")
        #expect((archive.date) >= (proof), "\(name)")
        guard case .good = signature.revocation else {
          Issue.record("\(name): the carried validation data did not answer the path")
          continue
        }
        print(
          "Verify \(name): valid \(signature.isValid), chain \(signature.chainVerified), "
            + "level \(signature.level?.label ?? "none"), "
            + "timestamps \(signature.timestamps.count), "
            + "archive timestamps \(signature.archiveTimestamps.count), "
            + "verifiable until \(validUntil.formatted(.iso8601))")
      }
    }

  }

#endif
