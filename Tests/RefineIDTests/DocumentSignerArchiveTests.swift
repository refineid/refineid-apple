// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import CryptoKit
  import Foundation
  import XCTest

  @testable import CardCore
  @testable import RefineIDTestHost

  /// A PDF document timestamp is accepted only when the validation
  /// material written under it carries its signer's whole path: a
  /// release build refuses one whose authority is outside the evidence,
  /// and a development build keeps the B-LT document.
  internal final class DocumentSignerArchiveTests: XCTestCase {
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

    override internal func setUp() async throws {
      try await super.setUp()
      let first = try DssGateAuthorities.make()
      evidenceAuthorities = first
      archiveAuthorities = try DssGateAuthorities.make()
      DssGateUrlProtocol.authorities = first
      DssGateUrlProtocol.timestampAuthorities = nil
      DssGateSessionHook.toggle()
      TrustRootsCache.shared.reset()
      TrustRootsCache.shared.register(first.caCertificate)
    }

    override internal func tearDown() async throws {
      DssGateSessionHook.toggle()
      DssGateUrlProtocol.authorities = nil
      DssGateUrlProtocol.timestampAuthorities = nil
      TrustRootsCache.shared.reset()
      try await super.tearDown()
    }

    /// A release build refuses a document timestamp whose authority's
    /// chain is not in the evidence it covers.
    internal func testReleaseRefusesAnArchiveAuthorityOutsideTheDss() async throws {
      let covered = try XCTUnwrap(evidenceAuthorities)
      let archive = try XCTUnwrap(archiveAuthorities)
      let stage = try Self.timestamped(covered)
      DssGateUrlProtocol.timestampAuthorities = archive
      let firstAnchor = covered.timestampCaCertificate
      let secondAnchor = archive.timestampCaCertificate
      let resolver: @Sendable (Date) -> [Data] = { _ in [firstAnchor, secondAnchor] }
      do {
        _ = try await TimestampClient.$anchorResolver.withValue(resolver) {
          try await DocumentSigner.longTerm(
            stage.signature,
            signerCertificate: covered.holderCertificate,
            timestampTokens: [stage.token],
            policy: .longTermOnly
          )
        }
        XCTFail("Expected the uncovered archive timestamp to be refused")
      } catch let failure as DocumentSigner.Failure {
        guard case .archiveTimestampUncovered = failure else {
          XCTFail("Expected archiveTimestampUncovered but got \(failure)")
          return
        }
      }
    }

    /// A rotated signer under the evidence's own timestamp authority is
    /// not covered: its certificate is outside the evidence even though
    /// it chains to an authority inside it.
    internal func testRotatedSignerUnderTheSameAuthorityIsRefused() async throws {
      let covered = try XCTUnwrap(evidenceAuthorities)
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
      let resolver: @Sendable (Date) -> [Data] = { _ in [anchor] }
      do {
        _ = try await TimestampClient.$anchorResolver.withValue(resolver) {
          try await DocumentSigner.longTerm(
            stage.signature,
            signerCertificate: covered.holderCertificate,
            timestampTokens: [stage.token],
            policy: .longTermOnly
          )
        }
        XCTFail("Expected the rotated archive signer to be refused")
      } catch let failure as DocumentSigner.Failure {
        guard case .archiveTimestampUncovered = failure else {
          XCTFail("Expected archiveTimestampUncovered but got \(failure)")
          return
        }
      }
    }

    /// A development build keeps the B-LT document and names its level
    /// when the archive timestamp's authority is outside the evidence.
    internal func testDevelopmentKeepsLongTermForAnUncoveredArchiveAuthority() async throws {
      let covered = try XCTUnwrap(evidenceAuthorities)
      let archive = try XCTUnwrap(archiveAuthorities)
      let stage = try Self.timestamped(covered)
      DssGateUrlProtocol.timestampAuthorities = archive
      let firstAnchor = covered.timestampCaCertificate
      let secondAnchor = archive.timestampCaCertificate
      let resolver: @Sendable (Date) -> [Data] = { _ in [firstAnchor, secondAnchor] }
      let product = try await TimestampClient.$anchorResolver.withValue(resolver) {
        try await DocumentSigner.longTerm(
          stage.signature,
          signerCertificate: covered.holderCertificate,
          timestampTokens: [stage.token],
          policy: .highestReached
        )
      }
      let shortfall = try XCTUnwrap(product.completion.shortfall)
      XCTAssertEqual(
        shortfall,
        BelowLongTermSignature(format: .pades, level: .longTerm, cause: .archiveTimestamp)
      )
      XCTAssertEqual(shortfall.nameMarker, Self.developmentLongTermMarker)
      XCTAssertEqual(shortfall.levelName, "PAdES B-LT")
      let bytes = String(bytes: product.bytes, encoding: .isoLatin1) ?? ""
      XCTAssertTrue(bytes.contains("/Type /DSS"))
      XCTAssertFalse(bytes.contains("/Type /DocTimeStamp"))
    }

    /// The same stage reaches the archival level when the evidence
    /// covers the authority that answers.
    internal func testCoveredArchiveAuthorityIsAccepted() async throws {
      let covered = try XCTUnwrap(evidenceAuthorities)
      let stage = try Self.timestamped(covered)
      DssGateUrlProtocol.timestampAuthorities = covered
      let anchor = covered.timestampCaCertificate
      let resolver: @Sendable (Date) -> [Data] = { _ in [anchor] }
      let product = try await TimestampClient.$anchorResolver.withValue(resolver) {
        try await DocumentSigner.longTerm(
          stage.signature,
          signerCertificate: covered.holderCertificate,
          timestampTokens: [stage.token],
          policy: .longTermOnly
        )
      }
      XCTAssertEqual(product.completion, .archival)
      let bytes = String(bytes: product.bytes, encoding: .isoLatin1) ?? ""
      XCTAssertTrue(bytes.contains("/Type /DocTimeStamp"))
    }
  }

#endif
