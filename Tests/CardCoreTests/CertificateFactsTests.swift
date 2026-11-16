// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// Direct X.509 field extraction checks used by chain, OCSP, and TSA
/// verification.
@Suite
internal struct CertificateFactsTests {
  /// Tags used only to assemble a minimal certificate fixture.
  private enum Tag {
    static let bitString: UInt8 = 0x03
    static let boolean: UInt8 = 0x01
    static let context0: UInt8 = 0xA0
    static let context3: UInt8 = 0xA3
    static let uri: UInt8 = 0x86
  }

  /// BOOLEAN FALSE content octet.
  private static let booleanFalse: UInt8 = 0x00

  /// id-ce-cRLDistributionPoints.
  private static let crlDistributionPoints = "2.5.29.31"

  /// id-ce-subjectKeyIdentifier.
  private static let subjectKeyIdentifier = "2.5.29.14"

  /// Synthetic SubjectKeyIdentifier payload octets.
  private static let keyIdentifier = Data("subject-key-identifier".utf8)

  /// A self-issued timestamp certificate with no AIA endpoints.
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

  /// Base64 fixture text with line breaks ignored.
  private static func decode(_ encoded: String) -> Data {
    Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) ?? Data()
  }

  /// A structurally sufficient certificate carrying caller-provided
  /// extension encodings.
  private static func certificate(extensions: [Data]) -> Data {
    let publicKey = DerEncoder.sequence([
      DerEncoder.sequence([]),
      DerEncoder.tlv(Tag.bitString, Data([0, 1])),
    ])
    let tbs = DerEncoder.sequence([
      DerEncoder.integer(1),
      DerEncoder.sequence([]),
      DerEncoder.sequence([]),
      DerEncoder.sequence([]),
      DerEncoder.sequence([]),
      publicKey,
      DerEncoder.tlv(
        Tag.context3,
        DerEncoder.sequence(extensions)
      ),
    ])
    return DerEncoder.sequence([tbs])
  }

  /// One full-name CRL distribution point.
  private static func distributionPoint(_ addresses: [String]) -> Data {
    let names = addresses.reduce(Data()) { partial, address in
      partial + DerEncoder.tlv(Tag.uri, Data(address.utf8))
    }
    let pointName = DerEncoder.tlv(
      Tag.context0,
      DerEncoder.tlv(Tag.context0, names)
    )
    return DerEncoder.sequence([pointName])
  }

  /// Names, serial, public key, endpoints, and timestamp EKU all come
  /// from the exact certificate encoding.
  @Test
  internal func requiredCertificateFieldsAreExtracted() throws {
    let facts = try #require(CertificateFacts(der: Self.certificate))

    #expect(!facts.serialNumber.isEmpty)
    #expect(!facts.publicKeyBits.isEmpty)
    #expect(facts.subjectKeyIdentifier != nil)
    #expect(facts.issuerName == facts.subjectName)
    #expect(facts.isSelfIssued)
    #expect(facts.issuerCertificateUrls.isEmpty)
    #expect(facts.ocspUrls.isEmpty)
    #expect(facts.crlUrls.isEmpty)
    #expect(facts.hasTimestampingExtendedKeyUsage)
  }

  /// A single non-critical SubjectKeyIdentifier exposes its inner octets,
  /// and an omitted extension reports nil.
  @Test
  internal func subjectKeyIdentifierExtractsValidOctetsAndNilWhenAbsent() throws {
    let validExtension = DerEncoder.sequence([
      DerEncoder.objectIdentifier(Self.subjectKeyIdentifier),
      DerEncoder.octetString(DerEncoder.octetString(Self.keyIdentifier)),
    ])
    let present = try #require(
      CertificateFacts(der: Self.certificate(extensions: [validExtension]))
    )
    let absent = try #require(
      CertificateFacts(der: Self.certificate(extensions: []))
    )

    #expect(present.subjectKeyIdentifier == Self.keyIdentifier)
    #expect(absent.subjectKeyIdentifier == nil)
  }

  /// Critical, malformed, or duplicate SubjectKeyIdentifier extensions fail
  /// closed to nil without rejecting the surrounding CertificateFacts.
  @Test
  internal func subjectKeyIdentifierFailsClosedWhenCriticalMalformedOrDuplicated() throws {
    let validExtension = DerEncoder.sequence([
      DerEncoder.objectIdentifier(Self.subjectKeyIdentifier),
      DerEncoder.octetString(DerEncoder.octetString(Self.keyIdentifier)),
    ])
    let criticalTrue = DerEncoder.sequence([
      DerEncoder.objectIdentifier(Self.subjectKeyIdentifier),
      DerEncoder.booleanTrue(),
      DerEncoder.octetString(DerEncoder.octetString(Self.keyIdentifier)),
    ])
    let explicitFalse = DerEncoder.sequence([
      DerEncoder.objectIdentifier(Self.subjectKeyIdentifier),
      DerEncoder.tlv(Tag.boolean, Data([Self.booleanFalse])),
      DerEncoder.octetString(DerEncoder.octetString(Self.keyIdentifier)),
    ])
    let nonOctetInner = DerEncoder.sequence([
      DerEncoder.objectIdentifier(Self.subjectKeyIdentifier),
      DerEncoder.octetString(DerEncoder.null()),
    ])
    let trailingInner = DerEncoder.sequence([
      DerEncoder.objectIdentifier(Self.subjectKeyIdentifier),
      DerEncoder.octetString(
        DerEncoder.octetString(Self.keyIdentifier) + DerEncoder.null()
      ),
    ])
    let trailingExtensionField = DerEncoder.sequence([
      DerEncoder.objectIdentifier(Self.subjectKeyIdentifier),
      DerEncoder.octetString(DerEncoder.octetString(Self.keyIdentifier)),
      DerEncoder.null(),
    ])

    for rejected in [
      [criticalTrue],
      [explicitFalse],
      [nonOctetInner],
      [trailingInner],
      [trailingExtensionField],
      [validExtension, validExtension],
    ] {
      let facts = try #require(
        CertificateFacts(der: Self.certificate(extensions: rejected))
      )
      #expect(facts.subjectKeyIdentifier == nil)
    }
  }

  /// Full-name HTTP distribution points are exposed once; unrelated
  /// GeneralName schemes are not sent to the signing network.
  @Test
  internal func crlDistributionPointUrlsAreExtractedAndDeduplicated() throws {
    let https = "https://ca.example/status.crl"
    let points = DerEncoder.sequence([
      Self.distributionPoint([
        https,
        "ldap://directory.example/status",
      ]),
      Self.distributionPoint([https, "http://ca.example/backup.crl"]),
    ])
    let extensionValue = DerEncoder.sequence([
      DerEncoder.objectIdentifier(Self.crlDistributionPoints),
      DerEncoder.octetString(points),
    ])
    let facts = try #require(
      CertificateFacts(
        der: Self.certificate(extensions: [extensionValue])
      )
    )

    #expect(
      facts.crlUrls == [
        https,
        "http://ca.example/backup.crl",
      ]
    )
  }

  /// Truncated and non-certificate values never expose partial facts.
  @Test
  internal func malformedCertificateReturnsNil() {
    #expect(CertificateFacts(der: Data()) == nil)
    #expect(CertificateFacts(der: Data("not a certificate".utf8)) == nil)
    #expect(
      CertificateFacts(der: Data(Self.certificate.dropLast())) == nil
    )
  }
}
