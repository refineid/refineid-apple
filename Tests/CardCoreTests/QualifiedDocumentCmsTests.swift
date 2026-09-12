// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security
import Testing

@testable import CardCore

/// Direct checks for the PAdES CMS structure built around a card
/// signature.
@Suite
internal struct QualifiedDocumentCmsTests {
  /// A malformed CMS fixture is a test construction failure.
  private enum FixtureFailure: Error {
    case malformedCms
  }

  /// A transient matching certificate and signing key.
  internal struct Identity {
    internal let certificate: Data
    internal let privateKey: SecKey
    internal let profile: CardKeyProfile
  }

  /// The exact signature fields of the sole SignerInfo.
  private struct SignerFields {
    let algorithm: Data
    let signature: Data
  }

  /// A fixed certificate with the fields IssuerAndSerialNumber needs.
  private static let certificate = Self.decode(
    """
    MIIBszCCAVigAwIBAgIUMHfE/GmdSvG3+CQRxHSnFzfP2IwwCgYIKoZIzj0EAwIwHDEaMBgGA1UE
    AwwRUmVGaW5lSUQgVGVzdCBUU0EwHhcNMjYwODA0MDc1MzI1WhcNMzYwODAxMDc1MzI1WjAcMRow
    GAYDVQQDDBFSZUZpbmVJRCBUZXN0IFRTQTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABEma/2Y8
    UqzBdNi9vlLoFQ+WHFW8PCTu67N0kmhjl18Eu0kEjTrtF6y5wF1VXf9ktFdnUJX+Rz6FES49kwG7
    cDujeDB2MB0GA1UdDgQWBBTY+L64mtIcQMUST9Jv2XCaRNeLmzAfBgNVHSMEGDAWgBTY+L64mtIc
    QMUST9Jv2XCaRNeLmzAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIGwDAWBgNVHSUBAf8EDDAK
    BggrBgEFBQcDCDAKBggqhkjOPQQDAgNJADBGAiEAwvyfmlibx6Pf8KmrY7VfgYwxbr56A80RBza/
    J4cPYlECIQCYsi5iogIH1DrFGEDBDrUrjaanfMOXp8GithjIM97ohg==
    """
  )

  /// Requires one parsed DER element without wrapping a mutating read in a
  /// testing macro.
  private static func required(
    _ element: DerReader.Element?
  ) throws -> DerReader.Element {
    guard let element else { throw FixtureFailure.malformedCms }
    return element
  }

  /// Base64 fixture text with line breaks ignored.
  private static func decode(_ encoded: String) -> Data {
    Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) ?? Data()
  }

  /// Builds one self-signed certificate with the selected card-key profile.
  internal static func identity(_ profile: CardKeyProfile) throws -> Identity {
    let keyType: CFString
    let kind: CertificateRevocationListFixtures.SignatureKind
    switch profile {
    case .ecdsaP256, .ecdsaP384:
      keyType = kSecAttrKeyTypeECSECPrimeRandom
      kind = .ecdsaSha384

    case .rsa2048, .rsa3072:
      keyType = kSecAttrKeyTypeRSA
      kind = .rsaSha384
    }
    let attributes: [CFString: Any] = [
      kSecAttrKeyType: keyType,
      kSecAttrKeySizeInBits: profile.keySizeInBits,
    ]
    var error: Unmanaged<CFError>?
    let privateKey = try #require(
      SecKeyCreateRandomKey(attributes as CFDictionary, &error)
    )
    let commonName = "RefineID Document CMS Test"
    let name = CertificateRevocationListFixtures.name(commonName)
    let encodedCertificate = try CertificateRevocationListFixtures.certificate(
      description: .init(
        allowsCrlSigning: false,
        includesKeyUsage: true,
        malformedKeyUsage: false,
        commonName: commonName,
        isCertificateAuthority: false,
        issuerName: name,
        serial: CertificateRevocationListFixtures.targetSerial
      ),
      publicKey: privateKey,
      signer: privateKey,
      kind: kind
    )
    return Identity(
      certificate: encodedCertificate, privateKey: privateKey, profile: profile
    )
  }

  /// Signs the SHA-384 digest of CMS signed attributes like the card does.
  internal static func signature(
    over attributes: Data,
    identity: Identity
  ) throws -> Data {
    let algorithm: SecKeyAlgorithm =
      identity.profile == .ecdsaP384
      ? .ecdsaSignatureDigestX962SHA384
      : .rsaSignatureDigestPKCS1v15SHA384
    let digest = Data(SHA384.hash(data: attributes))
    var error: Unmanaged<CFError>?
    return try #require(
      SecKeyCreateSignature(
        identity.privateKey, algorithm, digest as CFData, &error
      ) as Data?
    )
  }

  /// Parses the exact signature AlgorithmIdentifier and OCTET STRING value.
  private static func signerFields(in cms: Data) throws -> SignerFields {
    var outer = DerReader(cms)
    let contentInfo = try Self.required(outer.next())
    var contentInfoReader = DerReader(cms, within: contentInfo)
    _ = try Self.required(contentInfoReader.next())
    let explicitSignedData = try Self.required(contentInfoReader.next())
    var explicitReader = DerReader(cms, within: explicitSignedData)
    let signedData = try Self.required(explicitReader.next())
    var signedDataReader = DerReader(cms, within: signedData)
    _ = try Self.required(signedDataReader.next())
    _ = try Self.required(signedDataReader.next())
    _ = try Self.required(signedDataReader.next())
    var candidate = try Self.required(signedDataReader.next())
    if candidate.tag == DerValues.tagContext0Constructed {
      candidate = try Self.required(signedDataReader.next())
    }
    var signers = DerReader(cms, within: candidate)
    let signer = try Self.required(signers.next())
    var fields = DerReader(cms, within: signer)
    _ = try Self.required(fields.next())
    _ = try Self.required(fields.next())
    _ = try Self.required(fields.next())
    _ = try Self.required(fields.next())
    let algorithm = try Self.required(fields.next())
    let signature = try Self.required(fields.next())
    return SignerFields(
      algorithm: fields.data(of: algorithm),
      signature: fields.contentData(of: signature)
    )
  }

  /// The card signs attributes carrying the exact PDF digest and the
  /// SHA-384 hash of its signing certificate.
  @Test
  internal func signedAttributesBindDocumentAndCertificate() {
    let documentDigest = Data(repeating: 0xA5, count: 48)

    let attributes = QualifiedDocumentCms.signedAttributes(
      byteRangeDigest: documentDigest,
      signerCertificate: Self.certificate
    )

    #expect(attributes.contains(DerEncoder.octetString(documentDigest)))
    #expect(
      attributes.contains(
        DerEncoder.octetString(
          Data(SHA384.hash(data: Self.certificate))
        )
      )
    )
  }

  /// The assembled SignedData carries the signer certificate and the
  /// supplied signature timestamp token.
  @Test
  internal func assembledCmsCarriesCertificateAndTimestamp() throws {
    let identity = try Self.identity(.ecdsaP384)
    let attributes = QualifiedDocumentCms.signedAttributes(
      byteRangeDigest: Data(repeating: 0xA5, count: 48),
      signerCertificate: identity.certificate
    )
    let signatureValue = try Self.signature(over: attributes, identity: identity)
    let timestamp = DerEncoder.sequence([DerEncoder.integer(7)])

    let cms = try QualifiedDocumentCms.assemble(
      signedAttributesSet: attributes,
      signatureValue: signatureValue,
      signerProfile: identity.profile,
      signerCertificate: identity.certificate,
      timestampTokens: [timestamp]
    )

    #expect(CmsCertificates.inside(cms) == [identity.certificate])
    let fields = try Self.signerFields(in: cms)
    #expect(
      fields.algorithm
        == DerEncoder.sequence([
          DerEncoder.objectIdentifier("1.2.840.10045.4.3.3")
        ])
    )
    #expect(fields.signature == signatureValue)
    #expect(cms.contains(timestamp))
  }

  /// RSA uses its modulus-wide result unchanged and carries the SHA-384 RSA
  /// identifier with the required NULL parameter.
  @Test(arguments: [CardKeyProfile.rsa2048, .rsa3072])
  internal func rsaSignatureValueAndAlgorithmAreExact(
    _ profile: CardKeyProfile
  ) throws {
    let identity = try Self.identity(profile)
    let attributes = QualifiedDocumentCms.signedAttributes(
      byteRangeDigest: Data(repeating: 0xA5, count: 48),
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

    let rsaIdentifier = DerEncoder.sequence([
      DerEncoder.objectIdentifier("1.2.840.113549.1.1.12"),
      DerEncoder.null(),
    ])
    let fields = try Self.signerFields(in: cms)
    #expect(fields.algorithm == rsaIdentifier)
    #expect(fields.signature == signatureValue)
    let securityCertificate = try #require(
      SecCertificateCreateWithData(nil, identity.certificate as CFData)
    )
    let publicKey = try #require(SecCertificateCopyKey(securityCertificate))
    let digest = Data(SHA384.hash(data: attributes))
    var error: Unmanaged<CFError>?
    #expect(
      SecKeyVerifySignature(
        publicKey,
        .rsaSignatureDigestPKCS1v15SHA384,
        digest as CFData,
        signatureValue as CFData,
        &error
      )
    )
  }
}
