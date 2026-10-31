// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CryptoKit
  import Foundation
  import Testing

  @testable import CardCore

  /// Candidates, signer binding, CMS structure and timestamp states.
  extension DocumentVerificationReviewTests {
    /// A carried blob that is no certificate leaves the path intact.
    @Test
    internal func unparseableCandidateLeavesThePathIntact() throws {
      let fixture = try DocumentTrustFixture()
      let report = try Self.report(
        fixture, .init(storeCertificates: [Self.notACertificate, fixture.issuing]))

      #expect(report.chainVerified)
      #expect(report.isValid)
    }

    /// An ESS binding naming no carried certificate, or a
    /// SignerIdentifier naming another serial, leaves no signer.
    @Test
    internal func unboundSignerIsUnsupported() throws {
      let fixture = try DocumentTrustFixture()
      let otherBinding = try Self.entries(
        fixture, .init(cmsCertificates: [fixture.issuing], boundCertificate: fixture.root))
      let wrongSerial = try Self.entries(
        fixture, .init(cmsCertificates: [fixture.issuing], identifierSerial: Self.otherSerial))

      #expect(otherBinding.judged.isEmpty)
      #expect(otherBinding.signatures.count == 1)
      #expect(wrongSerial.judged.isEmpty)
      #expect(!wrongSerial.isValid)
    }

    /// A content-type attribute with two values is not valid; an
    /// EncapsulatedContentInfo carrying eContent is unsupported.
    @Test
    internal func cmsStructureIsStrict() throws {
      let fixture = try DocumentTrustFixture()
      let twoValues = try Self.report(
        fixture, .init(cmsCertificates: [fixture.issuing], duplicatesContentTypeValue: true))
      let attached = try Self.entries(
        fixture, .init(cmsCertificates: [fixture.issuing], encapsulatesContent: true))

      #expect(!twoValues.signatureValid)
      #expect(attached.judged.isEmpty)
    }

    /// SHA-512 imprints verify, an unknown hash is unsupported, a
    /// mismatch is invalid, and a signer without the time-stamping key
    /// purpose is never anchored.
    @Test
    internal func timestampStatesFollowTheToken() throws {
      let authority = try TimestampAuthorityFixture.make()
      func state(_ token: Data, anchors: [Data]) -> TimestampState {
        TimestampJudge.state(
          of: token,
          imprintMatches: { digest, imprint in imprint == digest.hash(Self.stampedBytes) },
          evidence: ValidationEvidence(),
          anchors: anchors,
          now: Date()
        )
      }
      let sha512 = try authority.token(
        imprint: Data(SHA512.hash(data: Self.stampedBytes)),
        algorithm: DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.sha512)]))
      let sha1 = try authority.token(
        imprint: Data(Insecure.SHA1.hash(data: Self.stampedBytes)),
        algorithm: DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.sha1)]))
      let mismatch = try authority.token(
        imprint: Data(SHA512.hash(data: Self.notACertificate)),
        algorithm: DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.sha512)]))

      guard case .anchored = state(sha512, anchors: [authority.certificate]) else {
        Issue.record("A SHA-512 imprint was not anchored")
        return
      }
      guard case .claimed = state(sha512, anchors: []) else {
        Issue.record("A token without anchors was not claimed")
        return
      }
      #expect(state(sha1, anchors: [authority.certificate]) == .unsupported)
      #expect(state(mismatch, anchors: [authority.certificate]) == .invalid)
      #expect(state(Self.notACertificate, anchors: [authority.certificate]) == .unsupported)
      #expect(throws: (any Error).self) {
        try TimestampTokenVerifier.verify(sha512, trustedCertificates: [])
      }

      let unfit = try SyntheticTimestampAuthority(carriesTimestampingUsage: false)
      let unfitToken = try unfit.token(
        imprint: Data(SHA384.hash(data: Self.stampedBytes)),
        generalizedTime: Self.currentTime)
      #expect(state(unfitToken, anchors: [unfit.certificate]) == .invalid)
    }
  }

#endif
