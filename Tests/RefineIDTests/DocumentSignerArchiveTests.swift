// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import CryptoKit
  import Foundation
  import Testing

  @testable import CardCore
  @testable import RefineIDTestHost

  /// A PDF document timestamp is accepted only when the validation
  /// material written under it carries its signer's whole path: a
  /// release build refuses one whose authority is outside the evidence,
  /// and a development build keeps the B-LT document.
  @Suite(.serialized, DssGateFixtureScope())
  internal final class DocumentSignerArchiveTests {
    /// The nonce the test's own signature timestamp echoes.
    private static let timestampNonce = Data("document archive test nonce".utf8)

    /// What a development output's name carries before its level.
    private static let developmentLongTermMarker = "-dev-B-LT"

    /// The authorities publishing the evidence.
    private var evidenceAuthorities: DssGateAuthorities?

    /// The authority answering only the archive timestamp.
    private var archiveAuthorities: DssGateAuthorities?

    /// The post-card signature and its timestamp, the stage before the
    /// validation material; the timestamp comes from the evidence's
    /// own authority without a network exchange.

    private static func timestamped(
      _ authorities: DssGateAuthorities
    ) throws -> (
      signature: DocumentSigner.TimestampedSignature,
      token: TimestampTokenVerifier.VerifiedToken
    ) {
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
      let signature = try DebugTimestampAuthority.sign(
        Data(SHA384.hash(data: attributes)),
        key: authorities.holderKey,
        algorithm: .rsaSignatureDigestPKCS1v15SHA384
      )
      let imprint = try QualifiedDocumentCms.signatureTimestampDigest(signatureValue: signature)
      let response = try authorities.timestampAuthority.response(
        imprint: imprint,
        nonce: Self.timestampNonce,
        generationTime: DebugTimestampAuthority.generationTime
      )
      let raw = try RfcTimestamp.token(
        fromResponse: response.response, digest: imprint, nonceBytes: Self.timestampNonce
      )
      let token = try TimestampTokenVerifier.verify(
        raw, trustedCertificates: [authorities.timestampCaCertificate]
      )
      let signatureTimestamped = try DocumentSigner.TimestampedSignature.verified(
        DocumentSigner.TimestampedSignatureInput(
          placeholder: placeholder,
          signedAttributes: attributes,
          signatureValue: signature,
          signerProfile: .rsa2048,
          signerCertificate: authorities.holderCertificate
        ),
        timestampTokens: [token]
      )
      return (signatureTimestamped, token)
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

    /// A release build refuses a document timestamp whose authority's
    /// chain is not in the evidence it covers.
    private func withFixture(_ operation: () async throws -> Void) async throws {
      let primary = try DssGateAuthorities.make()
      let archive = try DssGateAuthorities.make()
      evidenceAuthorities = primary
      archiveAuthorities = archive
      defer {
        evidenceAuthorities = nil
        archiveAuthorities = nil
      }
      try await DssGateSessionHook.withFixture(authorities: primary, performing: operation)
    }

    @Test
    internal func testReleaseRefusesAnArchiveAuthorityOutsideTheDss() async throws {
      try await withFixture {
        let covered = try #require(evidenceAuthorities)
        let archive = try #require(archiveAuthorities)
        let stage = try Self.timestamped(covered)
        DssGateUrlProtocol.timestampAuthorities = archive
        let firstAnchor = covered.timestampCaCertificate
        let secondAnchor = archive.timestampCaCertificate
        do {
          _ = try await Self.withSyntheticTimestampEnvironment(
            anchors: { _ in [firstAnchor, secondAnchor] },
            operation: {
              try await DocumentSigner.longTerm(
                stage.signature,
                signerCertificate: covered.holderCertificate,
                timestampTokens: [stage.token],
                policy: .longTermOnly
              )
            }
          )
          Issue.record("Expected the uncovered archive timestamp to be refused")
        } catch let failure as DocumentSigner.Failure {
          guard case .archiveTimestampUncovered = failure else {
            Issue.record("Expected archiveTimestampUncovered but got \(failure)")
            return
          }
        }

      }
    }

    /// A rotated signer under the evidence's own timestamp authority is
    /// not covered: its certificate is outside the evidence even though
    /// it chains to an authority inside it.
    @Test
    internal func testRotatedSignerUnderTheSameAuthorityIsRefused() async throws {
      try await withFixture {
        let covered = try #require(evidenceAuthorities)
        let rotated = try DebugTimestampAuthority.make(
          issuerKey: covered.timestampCaKey,
          issuerName: DebugTimestampAuthority.encodedName(
            DssGateAuthorities.timestampCaCommonName
          ),
          additionalExtensions: []
        )
        let stage = try Self.timestamped(covered)
        DssGateUrlProtocol.timestampAuthorities = covered.answeringTimestamps(with: rotated)
        let anchor = covered.timestampCaCertificate
        do {
          _ = try await Self.withSyntheticTimestampEnvironment(
            anchors: { _ in [anchor] },
            operation: {
              try await DocumentSigner.longTerm(
                stage.signature,
                signerCertificate: covered.holderCertificate,
                timestampTokens: [stage.token],
                policy: .longTermOnly
              )
            }
          )
          Issue.record("Expected the rotated archive signer to be refused")
        } catch let failure as DocumentSigner.Failure {
          guard case .archiveTimestampUncovered = failure else {
            Issue.record("Expected archiveTimestampUncovered but got \(failure)")
            return
          }
        }

      }
    }

    /// A development build keeps the B-LT document and names its level
    /// when the archive timestamp's authority is outside the evidence.
    @Test
    internal func testDevelopmentKeepsLongTermForAnUncoveredArchiveAuthority() async throws {
      try await withFixture {
        let covered = try #require(evidenceAuthorities)
        let archive = try #require(archiveAuthorities)
        let stage = try Self.timestamped(covered)
        DssGateUrlProtocol.timestampAuthorities = archive
        let firstAnchor = covered.timestampCaCertificate
        let secondAnchor = archive.timestampCaCertificate
        let product = try await Self.withSyntheticTimestampEnvironment(
          anchors: { _ in [firstAnchor, secondAnchor] },
          operation: {
            try await DocumentSigner.longTerm(
              stage.signature,
              signerCertificate: covered.holderCertificate,
              timestampTokens: [stage.token],
              policy: .highestReached
            )
          }
        )
        let shortfall = try #require(product.completion.shortfall)
        #expect(
          (shortfall)
            == (BelowLongTermSignature(format: .pades, level: .longTerm, cause: .archiveTimestamp)))
        #expect((shortfall.nameMarker) == (Self.developmentLongTermMarker))
        #expect((shortfall.levelName) == ("PAdES B-LT"))
        let bytes = String(bytes: product.bytes, encoding: .isoLatin1) ?? ""
        #expect((bytes.contains("/Type /DSS")))
        #expect(!(bytes.contains("/Type /DocTimeStamp")))

      }
    }

    /// The same stage reaches the archival level when the evidence
    /// covers the authority that answers.
    @Test
    internal func testCoveredArchiveAuthorityIsAccepted() async throws {
      try await withFixture {
        let covered = try #require(evidenceAuthorities)
        let stage = try Self.timestamped(covered)
        DssGateUrlProtocol.timestampAuthorities = covered
        let anchor = covered.timestampCaCertificate
        let product = try await Self.withSyntheticTimestampEnvironment(
          anchors: { _ in [anchor] },
          operation: {
            try await DocumentSigner.longTerm(
              stage.signature,
              signerCertificate: covered.holderCertificate,
              timestampTokens: [stage.token],
              policy: .longTermOnly
            )
          }
        )
        #expect((product.completion) == (.archival))
        let bytes = String(bytes: product.bytes, encoding: .isoLatin1) ?? ""
        #expect((bytes.contains("/Type /DocTimeStamp")))

      }
    }

  }

#endif
