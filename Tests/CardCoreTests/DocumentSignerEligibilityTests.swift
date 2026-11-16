// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security
import Testing

@testable import CardCore

/// Verifies X.509 KeyUsage and ExtendedKeyUsage eligibility for document signers.
@Suite
internal struct DocumentSignerEligibilityTests {
  /// DER BIT STRING content for `contentCommitment` (`0x40`, six trailing unused bits).
  internal static let contentCommitmentKeyUsage = Data([6, 0x40])

  /// DER BIT STRING content for `keyEncipherment` (`0x20`, five trailing unused bits).
  internal static let keyEnciphermentOnlyKeyUsage = Data([5, 0x20])

  /// DER BIT STRING content for `keyAgreement` (`0x08`, three trailing unused bits).
  private static let keyAgreementOnlyKeyUsage = Data([3, 0x08])

  /// DER BIT STRING content combining `digitalSignature` and `keyCertSign` (`0x84`, two unused bits).
  private static let digitalSignatureWithCertSignKeyUsage = Data([2, 0x84])

  /// DER BIT STRING content combining `digitalSignature` and `cRLSign` (`0x82`, one unused bit).
  private static let digitalSignatureWithCrlSignKeyUsage = Data([1, 0x82])

  /// Encodes an `ExtendedKeyUsage` extension carrying the given dotted OIDs.
  internal static func extendedKeyUsageExtension(oids: [String], critical: Bool) -> Data {
    CertificateRevocationListFixtures.extensionValue(
      oid: SignOids.extendedKeyUsage,
      critical: critical,
      value: DerEncoder.sequence(oids.map(DerEncoder.objectIdentifier))
    )
  }

  /// Generates a leaf certificate with caller-controlled KeyUsage and extra extensions.
  private static func makeLeafCertificate(
    includesKeyUsage: Bool = true,
    customKeyUsageContent: Data? = nil,
    additionalExtensions: [Data] = []
  ) throws -> Data {
    let issuerKey = try CertificateRevocationListFixtures.makeKey(for: .ecdsaSha256)
    let leafKey = try CertificateRevocationListFixtures.makeKey(for: .ecdsaSha256)
    return try CertificateRevocationListFixtures.certificate(
      description: .init(
        allowsCrlSigning: false,
        includesKeyUsage: includesKeyUsage,
        malformedKeyUsage: false,
        commonName: CertificateRevocationListFixtures.targetCommonName,
        isCertificateAuthority: false,
        issuerName: CertificateRevocationListFixtures.name(
          CertificateRevocationListFixtures.issuerCommonName
        ),
        serial: CertificateRevocationListFixtures.targetSerial,
        customKeyUsageContent: customKeyUsageContent,
        additionalExtensions: additionalExtensions
      ),
      publicKey: leafKey,
      signer: issuerKey,
      kind: .ecdsaSha256
    )
  }

  /// Accepts `digitalSignature` and `contentCommitment` leaves without EKU or with document-compatible EKUs.
  @Test
  internal func acceptsValidSigningKeyUsagesAndCompatibleExtendedKeyUsages() throws {
    let digitalSignatureLeaf = try Self.makeLeafCertificate()
    let contentCommitmentLeaf = try Self.makeLeafCertificate(
      customKeyUsageContent: Self.contentCommitmentKeyUsage
    )
    #expect(CertificatePath.isFitToSign(digitalSignatureLeaf))
    #expect(CertificatePath.isFitToSign(contentCommitmentLeaf))

    let compatiblePurposeSets: [[String]] = [
      [SignOids.documentSigning],
      [SignOids.emailProtection],
      [SignOids.adobePdfSigning],
      [SignOids.microsoftDocumentSigning],
      [SignOids.anyExtendedKeyUsage],
      [SignOids.clientAuthentication, SignOids.emailProtection],
      [SignOids.serverAuthentication, SignOids.documentSigning],
    ]
    for purposes in compatiblePurposeSets {
      for critical in [false, true] {
        let leaf = try Self.makeLeafCertificate(
          additionalExtensions: [Self.extendedKeyUsageExtension(oids: purposes, critical: critical)]
        )
        #expect(CertificatePath.isFitToSign(leaf))
      }
    }
  }

  /// Rejects missing, encryption-only, key-agreement-only, and CA-bit KeyUsage values for document signing.
  @Test
  internal func rejectsMissingNonSigningOrAuthorityKeyUsageBits() throws {
    let withoutKeyUsage = try Self.makeLeafCertificate(includesKeyUsage: false)
    let keyEnciphermentOnly = try Self.makeLeafCertificate(
      customKeyUsageContent: Self.keyEnciphermentOnlyKeyUsage
    )
    let keyAgreementOnly = try Self.makeLeafCertificate(
      customKeyUsageContent: Self.keyAgreementOnlyKeyUsage
    )
    let withCertSign = try Self.makeLeafCertificate(
      customKeyUsageContent: Self.digitalSignatureWithCertSignKeyUsage
    )
    let withCrlSign = try Self.makeLeafCertificate(
      customKeyUsageContent: Self.digitalSignatureWithCrlSignKeyUsage
    )

    #expect(!CertificatePath.isFitToSign(withoutKeyUsage))
    #expect(!CertificatePath.isFitToSign(keyEnciphermentOnly))
    #expect(!CertificatePath.isFitToSign(keyAgreementOnly))
    #expect(!CertificatePath.isFitToSign(withCertSign))
    #expect(!CertificatePath.isFitToSign(withCrlSign))

    // Generic revocation-subject checks continue to recognize non-signing end-entity leaves.
    let parsedEncipherment = try #require(CertificateIssuer.parsed(keyEnciphermentOnly))
    #expect(CertificateIssuer.isPermittedEndEntity(parsedEncipherment))
  }

  /// Rejects incompatible or malformed ExtendedKeyUsage extensions whether critical or non-critical.
  @Test
  internal func rejectsIncompatibleAndMalformedExtendedKeyUsages() throws {
    let incompatiblePurposeSets: [[String]] = [
      [SignOids.serverAuthentication],
      [SignOids.clientAuthentication],
      [SignOids.ocspSigning],
      [SignOids.timestampingKeyPurpose],
      [SignOids.serverAuthentication, SignOids.clientAuthentication],
    ]
    for purposes in incompatiblePurposeSets {
      for critical in [false, true] {
        let leaf = try Self.makeLeafCertificate(
          additionalExtensions: [Self.extendedKeyUsageExtension(oids: purposes, critical: critical)]
        )
        #expect(!CertificatePath.isFitToSign(leaf))
      }
    }

    let emptyEku = try Self.makeLeafCertificate(
      additionalExtensions: [Self.extendedKeyUsageExtension(oids: [], critical: false)]
    )
    let duplicateEku = try Self.makeLeafCertificate(
      additionalExtensions: [
        Self.extendedKeyUsageExtension(
          oids: [SignOids.documentSigning, SignOids.documentSigning],
          critical: false
        )
      ]
    )
    #expect(!CertificatePath.isFitToSign(emptyEku))
    #expect(!CertificatePath.isFitToSign(duplicateEku))
  }
}
