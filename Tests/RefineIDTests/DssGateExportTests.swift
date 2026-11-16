// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import CryptoKit
  import Foundation
  import Security
  import XCTest

  @testable import CardCore
  @testable import RefineIDTestHost

  /// Signs a PDF and an ASiC-E container through the production stages
  /// that decide their level, against the synthetic authorities, and
  /// exports them for the EU DSS validator (`Scripts/dss-gate.sh`).
  ///
  /// The card is the only stand-in: a generated RSA-2048 key signs what
  /// the card would sign. From the card's answer on, the code is the
  /// app's: `TimestampClient`, `DocumentSigner.longTerm` and
  /// `AsicSigner.evidenced`, over the app's own signing network, whose
  /// requests `DssGateUrlProtocol` answers in memory. What level the
  /// files reach is for DSS to say, not this test.
  internal final class DssGateExportTests: XCTestCase {
    /// Where the files go: the test host's temporary directory, which
    /// `Scripts/dss-gate.sh` reads.
    private static var exportDirectory: URL {
      FileManager.default.temporaryDirectory.appending(
        path: "RefineIDDssGate", directoryHint: .isDirectory
      )
    }

    private static let containedFileName = "terms.txt"
    private static let containedFileText = "Terms agreed under the DSS gate."
    private static let testDigestByteCount = 48
    private static let testDigestPattern: UInt8 = 0x42

    /// The PDF as `DocumentSigner.sign` finishes it after the card.
    private static func signedPdf(_ authorities: DssGateAuthorities) async throws -> Data {
      let placeholder = try PdfIncrementalSigner.prepare(
        TimestampedPdfFixture.minimalPdf,
        revision: .signature(
          PdfIncrementalSigner.SignatureClaim(signedAt: Date(), reason: nil, location: nil)
        )
      )
      let attributes = QualifiedDocumentCms.signedAttributes(
        byteRangeDigest: placeholder.digest(QualifiedDocumentCms.signingDigestAlgorithm),
        signerCertificate: authorities.holderCertificate
      )
      let signature = try Self.cardSignature(
        Data(SHA384.hash(data: attributes)),
        key: authorities.holderKey,
        algorithm: .rsaSignatureDigestPKCS1v15SHA384
      )
      return try await TimestampClient.forOneDocument {
        let token = try await TimestampClient.token(
          over: QualifiedDocumentCms.signatureTimestampDigest(signatureValue: signature)
        )
        let timestamped = try DocumentSigner.TimestampedSignature.verified(
          DocumentSigner.TimestampedSignatureInput(
            placeholder: placeholder,
            signedAttributes: attributes,
            signatureValue: signature,
            signerProfile: .rsa2048,
            signerCertificate: authorities.holderCertificate
          ),
          timestampTokens: [token]
        )
        return try await DocumentSigner.longTerm(
          timestamped,
          signerCertificate: authorities.holderCertificate,
          timestampTokens: [token],
          policy: .longTermOnly
        ).bytes
      }
    }

    /// The container as `AsicSigner.sign` finishes it after the card.
    private static func signedContainer(
      _ authorities: DssGateAuthorities
    ) async throws -> Data {
      let objects = [
        AsicSigner.dataObject(
          Data(Self.containedFileText.utf8), named: Self.containedFileName
        )
      ]
      let plan = try XCTUnwrap(
        XadesSignature.plan(
          objects: objects,
          certificate: authorities.holderCertificate,
          profile: .rsa2048,
          signedAt: Date()
        )
      )
      let wire = try Self.cardSignature(
        plan.signedInfo,
        key: authorities.holderKey,
        algorithm: .rsaSignatureMessagePKCS1v15SHA384
      )
      let xmlSignature = try XCTUnwrap(CardKeyProfile.rsa2048.xmlSignature(fromWire: wire))
      return try await AsicSigner.evidenced(
        plan: plan,
        xmlSignature: xmlSignature,
        certificate: authorities.holderCertificate,
        objects: objects,
        completion: AsicSigner.Completion(sources: .live, policy: .longTermOnly)
      ).bytes
    }

    /// What the card answers: one RSA PKCS #1 signature.
    private static func cardSignature(
      _ value: Data,
      key: SecKey,
      algorithm: SecKeyAlgorithm
    ) throws -> Data {
      try DebugTimestampAuthority.sign(value, key: key, algorithm: algorithm)
    }

    /// Runs `operation` with synthetic anchors and zero inter-document sleep
    /// against the in-memory gate responder.
    private static func withSyntheticTimestampEnvironment<Value>(
      anchors: @escaping @Sendable (Date) -> [Data],
      operation: () async throws -> Value
    ) async rethrows -> Value {
      try await TimestampClient.$throttle.withValue(TimestampThrottle(spacing: .zero)) {
        try await TimestampClient.$anchorResolver.withValue(anchors) {
          try await operation()
        }
      }
    }

    override internal func setUp() async throws {
      try await super.setUp()
      let authorities = try DssGateAuthorities.make()
      DssGateUrlProtocol.authorities = authorities
      DssGateSessionHook.toggle()
      TrustRootsCache.shared.reset()
      TrustRootsCache.shared.register(authorities.caCertificate)
    }

    override internal func tearDown() async throws {
      DssGateSessionHook.toggle()
      DssGateUrlProtocol.authorities = nil
      TrustRootsCache.shared.reset()
      try await super.tearDown()
    }

    /// Writes `swift-pades.pdf`, `swift-asic-e.asice` and the anchors
    /// DSS is to trust.
    internal func testExportsPdfAndAsicSignaturesForDss() async throws {
      let authorities = try XCTUnwrap(DssGateUrlProtocol.authorities)
      let tsCaCertificate = authorities.timestampCaCertificate
      try await Self.withSyntheticTimestampEnvironment(
        anchors: { _ in [tsCaCertificate] },
        operation: {
          let directory = Self.exportDirectory
          try? FileManager.default.removeItem(at: directory)
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          try authorities.caCertificate.write(to: directory.appending(path: "anchor-ca.der"))
          try authorities.timestampCaCertificate.write(
            to: directory.appending(path: "anchor-tsa.der")
          )
          let pdf = try await Self.signedPdf(authorities)
          try pdf.write(to: directory.appending(path: "swift-pades.pdf"))
          let container = try await Self.signedContainer(authorities)
          try container.write(to: directory.appending(path: "swift-asic-e.asice"))
          print("DSS gate export: \(directory.path)")
        }
      )
    }

    /// Live token(over:) verifies a signer chained to a separate CA anchor.
    internal func testLiveTokenOverAuthenticatesSignerChainedToCaAnchor() async throws {
      let authorities = try XCTUnwrap(DssGateUrlProtocol.authorities)
      let digest = Data(repeating: Self.testDigestPattern, count: Self.testDigestByteCount)
      let tsCaCertificate = authorities.timestampCaCertificate
      let verified = try await Self.withSyntheticTimestampEnvironment(
        anchors: { _ in [tsCaCertificate] },
        operation: {
          try await TimestampClient.token(over: digest)
        }
      )
      XCTAssertEqual(verified.signerCertificate, authorities.timestampAuthority.certificate)
      XCTAssertEqual(verified.trustedCertificate, authorities.timestampCaCertificate)
      XCTAssertEqual(
        verified.verifiedCertificateChain,
        [
          authorities.timestampAuthority.certificate,
          authorities.timestampCaCertificate,
        ]
      )
    }

    /// Live token(over:) rejects a timestamp signer not anchored at the trusted CA.
    internal func testLiveTokenOverRejectsSignerNotAnchoredAtCa() async throws {
      let authorities = try XCTUnwrap(DssGateUrlProtocol.authorities)
      let digest = Data(repeating: Self.testDigestPattern, count: Self.testDigestByteCount)
      let caCertificate = authorities.caCertificate
      do {
        _ = try await Self.withSyntheticTimestampEnvironment(
          anchors: { _ in [caCertificate] },
          operation: {
            try await TimestampClient.token(over: digest)
          }
        )
        XCTFail("Expected untrustedAuthority failure")
      } catch let error as TimestampClient.Failure {
        guard case .untrustedAuthority = error else {
          XCTFail("Expected .untrustedAuthority but got \(error)")
          return
        }
      } catch {
        XCTFail("Unexpected error: \(error)")
      }
    }

    /// The verifier the Mac's Verify button runs reads both release
    /// signatures as B-LTA under the gate's CA and authority alone, the
    /// archive timestamp anchored after the signature timestamp.
    internal func testOwnVerifierReadsBothAtLongTermArchival() async throws {
      let authorities = try XCTUnwrap(DssGateUrlProtocol.authorities)
      let tsCaCertificate = authorities.timestampCaCertificate
      try await Self.withSyntheticTimestampEnvironment(
        anchors: { _ in [tsCaCertificate] },
        operation: {
          try await self.assertDocumentsReadAtLongTermArchival(authorities: authorities)
        }
      )
    }

    /// Signing a PDF followed by an ASiC-E container under the 15-second
    /// throttle waits once between the two documents, never between a
    /// document's own signature and archive timestamps, and never on a
    /// Settings probe.
    internal func testShippedThrottleSpacesSeparateDocumentsAndExemptsProbes() async throws {
      let authorities = try XCTUnwrap(DssGateUrlProtocol.authorities)
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
          _ = try await Self.signedPdf(authorities)
          XCTAssertTrue(clock.sleeps.isEmpty)

          _ = try await Self.signedContainer(authorities)
          XCTAssertEqual(clock.sleeps, [TimestampThrottle.minimumDocumentSpacing])

          try await TimestampClient.probe(TimestampClient.authority(in: .standard))
          XCTAssertEqual(clock.sleeps, [TimestampThrottle.minimumDocumentSpacing])
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
        ("swift-pades.pdf", try await Self.signedPdf(authorities)),
        ("swift-asic-e.asice", try await Self.signedContainer(authorities)),
      ]
      for (name, document) in documents {
        let report = try DocumentVerification.verify(document: document, anchors: anchors)
        XCTAssertEqual(report.signatures.count, 1, name)
        guard case .judged(let signature) = report.signatures.first else {
          XCTFail("\(name): the signature was not judged")
          continue
        }
        XCTAssertTrue(signature.isValid, name)
        XCTAssertTrue(signature.chainVerified, name)
        XCTAssertEqual(signature.level, .longTermArchival, name)
        let validUntil = try XCTUnwrap(signature.archiveValidUntil, name)
        XCTAssertGreaterThan(validUntil, Date(), name)
        let proof = try XCTUnwrap(signature.proofOfExistence, name)
        let archive = try XCTUnwrap(
          signature.archiveTimestamps.compactMap(\.provenTime).max(), name)
        XCTAssertGreaterThanOrEqual(archive.date, proof, name)
        guard case .good = signature.revocation else {
          XCTFail("\(name): the carried validation data did not answer the path")
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
