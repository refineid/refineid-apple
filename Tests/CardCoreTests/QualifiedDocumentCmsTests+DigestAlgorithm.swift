// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security
import Testing

@testable import CardCore

/// PAdES verification across the accepted SignerInfo digest algorithms
/// and every card-key profile (ETSI EN 319 142-1 clause 6.3).
extension QualifiedDocumentCmsTests {
  /// The fields of one hand-built PAdES CMS, in the form another
  /// generator writes.
  internal struct ForeignCms {
    internal let identity: Identity
    internal let signerDigest: String
    internal let signatureDigest: DocumentDigestAlgorithm
    internal let signatureAlgorithm: Data
  }

  /// The low bit of a byte, flipped to corrupt a signature value.
  private static let corruptingBit: UInt8 = 1

  /// sha256WithRSAEncryption with its NULL parameter (RFC 8017).
  internal static var sha256WithRsa: Data {
    DerEncoder.sequence([
      DerEncoder.objectIdentifier(SignOids.sha256WithRsa), DerEncoder.null(),
    ])
  }

  /// A prepared signature revision of the minimal PDF.
  internal static func placeholder() throws -> PdfSignaturePlaceholder {
    try PdfIncrementalSigner.prepare(
      PdfIncrementalSignerTests.minimalPdf,
      revision: .signature(
        PdfIncrementalSigner.SignatureClaim(
          signedAt: Date(timeIntervalSince1970: 0), reason: nil, location: nil
        )
      )
    )
  }

  /// The one signature report of a filled document.
  internal static func report(
    _ placeholder: PdfSignaturePlaceholder,
    cms: Data
  ) throws -> DocumentVerification.SignatureReport {
    let document = try placeholder.filled(with: cms)
    let report = try DocumentVerification.verify(document: document)
    #expect(report.signatures.count == 1)
    return try #require(report.signatures.first)
  }

  /// One attribute: its OID and one value in a SET.
  private static func attribute(_ oid: String, value: Data) -> Data {
    DerEncoder.sequence([
      DerEncoder.objectIdentifier(oid),
      DerEncoder.tlv(DerValues.tagSet, value),
    ])
  }

  /// The three signed attributes with an ESSCertIDv2 whose hash
  /// algorithm is left to its SHA-256 DER default (RFC 5035 section 4).
  internal static func sha256SignedAttributes(
    byteRangeDigest: Data,
    certificate: Data
  ) -> Data {
    let essCertId = DerEncoder.sequence([
      DerEncoder.octetString(Data(SHA256.hash(data: certificate)))
    ])
    return DerEncoder.setOf([
      Self.attribute(
        SignOids.contentType, value: DerEncoder.objectIdentifier(SignOids.data)
      ),
      Self.attribute(
        SignOids.messageDigest, value: DerEncoder.octetString(byteRangeDigest)
      ),
      Self.attribute(
        SignOids.signingCertificateV2,
        value: DerEncoder.sequence([DerEncoder.sequence([essCertId])])
      ),
    ])
  }

  /// A detached SignedData over `attributes` with one SignerInfo.
  internal static func contentInfo(
    _ fields: ForeignCms,
    attributes: Data
  ) throws -> Data {
    try Self.contentInfo(fields, attributes: attributes) { _ in [] }
  }

  /// The same, with the signature-timestamp tokens `timestamps` mints
  /// over the signature value.
  internal static func contentInfo(
    _ fields: ForeignCms,
    attributes: Data,
    timestamps: (Data) throws -> [Data]
  ) throws -> Data {
    let signature = try Self.signature(
      over: attributes,
      identity: fields.identity,
      digestAlgorithm: fields.signatureDigest
    )
    let digestIdentifier = DerEncoder.sequence([
      DerEncoder.objectIdentifier(fields.signerDigest)
    ])
    let issuerAndSerial = DerEncoder.sequence([
      CertificateRevocationListFixtures.name(Self.identityCommonName),
      DerEncoder.unsignedInteger(CertificateRevocationListFixtures.targetSerial),
    ])
    var signerFields = [
      DerEncoder.integer(SignOids.signerInfoVersion),
      issuerAndSerial,
      digestIdentifier,
      DerEncoder.retagged(attributes, to: DerValues.tagContext0Constructed),
      fields.signatureAlgorithm,
      DerEncoder.octetString(signature),
    ]
    let tokens = try timestamps(signature)
    if !tokens.isEmpty {
      let instances = tokens.map { token in
        Self.attribute(SignOids.signatureTimestampToken, value: token)
      }
      signerFields.append(
        DerEncoder.retagged(
          DerEncoder.setOf(instances), to: DerValues.tagContext1Constructed
        )
      )
    }
    let signerInfo = DerEncoder.sequence(signerFields)
    let signedData = DerEncoder.sequence([
      DerEncoder.integer(SignOids.cmsVersion),
      DerEncoder.tlv(DerValues.tagSet, digestIdentifier),
      DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.data)]),
      DerEncoder.tlv(DerValues.tagContext0Constructed, fields.identity.certificate),
      DerEncoder.tlv(DerValues.tagSet, signerInfo),
    ])
    return DerEncoder.sequence([
      DerEncoder.objectIdentifier(SignOids.signedData),
      DerEncoder.tlv(DerValues.tagContext0Constructed, signedData),
    ])
  }

  /// The assembler accepts a P-256 card signature, the verifier
  /// reports it valid, and one flipped bit makes it invalid.
  @Test
  internal func p256SignatureVerifiesAndACorruptedOneDoesNot() throws {
    let identity = try Self.identity(.ecdsaP256)
    let placeholder = try Self.placeholder()
    let attributes = QualifiedDocumentCms.signedAttributes(
      byteRangeDigest: placeholder.digest(
        QualifiedDocumentCms.signingDigestAlgorithm
      ),
      signerCertificate: identity.certificate
    )
    let signatureValue = try Self.signature(over: attributes, identity: identity)
    let cms = try QualifiedDocumentCms.assemble(
      signedAttributesSet: attributes,
      signatureValue: signatureValue,
      signerProfile: identity.profile,
      signerCertificate: identity.certificate,
      timestampTokens: []
    )

    let valid = try Self.report(placeholder, cms: cms)
    #expect(valid.documentIntact)
    #expect(valid.signatureValid)

    let location = try #require(cms.range(of: signatureValue))
    var corrupted = cms
    corrupted[cms.index(before: location.upperBound)] ^= Self.corruptingBit
    let invalid = try Self.report(placeholder, cms: corrupted)
    #expect(invalid.documentIntact)
    #expect(!invalid.signatureValid)
  }

  /// An RSA PAdES signature digested with SHA-256 throughout, its
  /// ESSCertIDv2 carrying the DER-default hash algorithm implicitly,
  /// verifies intact and valid.
  @Test(arguments: [CardKeyProfile.rsa2048, .rsa3072])
  internal func sha256RsaSignatureVerifies(_ profile: CardKeyProfile) throws {
    let identity = try Self.identity(profile)
    let placeholder = try Self.placeholder()
    let attributes = Self.sha256SignedAttributes(
      byteRangeDigest: placeholder.digest(.sha256),
      certificate: identity.certificate
    )
    let cms = try Self.contentInfo(
      ForeignCms(
        identity: identity,
        signerDigest: SignOids.sha256,
        signatureDigest: .sha256,
        signatureAlgorithm: Self.sha256WithRsa
      ),
      attributes: attributes
    )

    let report = try Self.report(placeholder, cms: cms)
    #expect(report.documentIntact)
    #expect(report.signatureValid)
  }

  /// A SHA-256 ECDSA signature verifies with the X9.62 SHA-256 algorithm.
  @Test(arguments: [CardKeyProfile.ecdsaP256, .ecdsaP384])
  internal func sha256EcdsaSignatureVerifies(_ profile: CardKeyProfile) throws {
    let identity = try Self.identity(profile)
    let placeholder = try Self.placeholder()
    let attributes = Self.sha256SignedAttributes(
      byteRangeDigest: placeholder.digest(.sha256),
      certificate: identity.certificate
    )
    let cms = try Self.contentInfo(
      ForeignCms(
        identity: identity,
        signerDigest: SignOids.sha256,
        signatureDigest: .sha256,
        signatureAlgorithm: DerEncoder.sequence([
          DerEncoder.objectIdentifier(SignOids.ecdsaWithSha256)
        ])
      ),
      attributes: attributes
    )

    let report = try Self.report(placeholder, cms: cms)
    #expect(report.documentIntact)
    #expect(report.signatureValid)
  }

  /// A SignerInfo digest algorithm other than SHA-256 or SHA-384 is
  /// refused as unsupported.
  @Test(arguments: [SignOids.sha1, SignOids.sha512])
  internal func otherDigestAlgorithmsAreUnsupported(_ oid: String) throws {
    let identity = try Self.identity(.rsa2048)
    let placeholder = try Self.placeholder()
    let attributes = Self.sha256SignedAttributes(
      byteRangeDigest: placeholder.digest(.sha256),
      certificate: identity.certificate
    )
    let cms = try Self.contentInfo(
      ForeignCms(
        identity: identity,
        signerDigest: oid,
        signatureDigest: .sha256,
        signatureAlgorithm: Self.sha256WithRsa
      ),
      attributes: attributes
    )

    #expect(
      throws: QualifiedDocumentCms.ReadFailure.unsupportedDigestAlgorithm
    ) {
      _ = try QualifiedDocumentCms.read(cms)
    }
    let document = try placeholder.filled(with: cms)
    #expect(throws: DocumentVerification.Failure.unsupportedProfile) {
      _ = try DocumentVerification.verify(document: document)
    }
  }

  /// A SHA-384 SignerInfo over a SHA-256 message digest is neither
  /// intact nor valid, even with the signature made over SHA-384.
  @Test
  internal func digestAlgorithmAndMessageDigestMustAgree() throws {
    let identity = try Self.identity(.rsa2048)
    let placeholder = try Self.placeholder()
    let attributes = Self.sha256SignedAttributes(
      byteRangeDigest: placeholder.digest(.sha256),
      certificate: identity.certificate
    )
    let cms = try Self.contentInfo(
      ForeignCms(
        identity: identity,
        signerDigest: SignOids.sha384,
        signatureDigest: .sha384,
        signatureAlgorithm: DerEncoder.sequence([
          DerEncoder.objectIdentifier(SignOids.sha384WithRsa), DerEncoder.null(),
        ])
      ),
      attributes: attributes
    )

    let report = try Self.report(placeholder, cms: cms)
    #expect(!report.documentIntact)
    #expect(!report.signatureValid)
  }

  /// The canonical SHA-256 attributes leave the ESSCertIDv2 hash
  /// algorithm out, and the SHA-384 ones name it.
  @Test
  internal func essCertIdNamesOnlyANonDefaultHash() throws {
    let identity = try Self.identity(.rsa2048)
    let placeholder = try Self.placeholder()
    let sha256Digest = placeholder.digest(.sha256)
    #expect(
      QualifiedDocumentCms.signedAttributes(
        byteRangeDigest: sha256Digest,
        signerCertificate: identity.certificate,
        digestAlgorithm: .sha256
      )
        == Self.sha256SignedAttributes(
          byteRangeDigest: sha256Digest, certificate: identity.certificate
        )
    )
    let sha384 = QualifiedDocumentCms.signedAttributes(
      byteRangeDigest: placeholder.digest(.sha384),
      signerCertificate: identity.certificate
    )
    #expect(
      sha384.contains(
        DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.sha384)])
      )
    )
  }
}
