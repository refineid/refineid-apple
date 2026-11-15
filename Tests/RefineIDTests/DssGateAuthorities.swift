// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import Foundation
  import Security

  @testable import CardCore
  @testable import RefineIDTestHost

  /// The synthetic authorities the DSS gate signs against.
  ///
  /// A CA issues the card's qualified certificate and publishes its
  /// CRL; the generated test timestamp authority answers the app's
  /// configured authority. Every certificate is valid around the
  /// current time, because the production stages judge evidence
  /// against the clock.
  internal struct DssGateAuthorities {
    /// Failures mean the synthetic material could not be constructed.
    internal enum Failure: Error {
      case key
      case signature
    }

    /// The host every certificate-published address names: a public
    /// numeric address, so the signing network asks no resolver, and
    /// the gate's URL protocol answers before any connection is made.
    internal static let host = "1.1.1.1"

    /// The CA's CRL, named by the qualified certificate.
    internal static let revocationListAddress = "http://1.1.1.1/dss-gate-ca.crl"

    internal static let caCommonName = "RefineID DSS Gate Test CA"
    internal static let timestampCaCommonName = "RefineID DSS Gate Test TSA CA"
    internal static let holderCommonName = "RefineID DSS Gate Test Holder"
    internal static let caSerial = 1
    internal static let holderSerial = 2
    internal static let timestampCaSerial = 3
    internal static let revocationListNumber = 1
    internal static let timestampRevocationListNumber = 2
    internal static let timestampRevocationListAddress = "http://1.1.1.1/dss-gate-tsa-ca.crl"
    internal static let crlVersionTwo = 1
    internal static let p256KeySize = 256
    internal static let rsaKeySize = 2_048
    internal static let secondsPerHour: TimeInterval = 3_600
    internal static let hoursPerDay: TimeInterval = 24
    internal static let daysPerYear: TimeInterval = 365
    internal static let validityMargin = secondsPerHour * hoursPerDay * daysPerYear
    internal static let revocationListAge = secondsPerHour
    internal static let revocationListLifetime = secondsPerHour * hoursPerDay
    internal static let nonRepudiationBit: UInt8 = 0x40
    internal static let keyUsageUnusedBitsNonRepudiation: UInt8 = 6
    internal static let keyUsageUnusedBitsCa: UInt8 = 1
    /// The octet DER puts before a positive INTEGER whose top bit is set.
    internal static let integerSignOctet: UInt8 = 0

    /// The self-signed CA certificate, the signer's trust anchor.
    internal let caCertificate: Data

    /// The CA's generated P-256 key.
    internal let caKey: SecKey

    /// The self-signed CA certificate for the timestamp authority.
    internal let timestampCaCertificate: Data

    /// The timestamp CA's generated P-256 key.
    internal let timestampCaKey: SecKey

    /// The card's qualified certificate, issued by the CA.
    internal let holderCertificate: Data

    /// The card's generated RSA-2048 key.
    internal let holderKey: SecKey

    /// The generated timestamp authority.
    internal let timestampAuthority: DebugTimestampAuthority

    /// Builds fresh keys and certificates.
    internal static func make() throws -> Self {
      let issuerKey = try Self.key(type: kSecAttrKeyTypeECSECPrimeRandom, size: Self.p256KeySize)
      let tsCaKey = try Self.key(type: kSecAttrKeyTypeECSECPrimeRandom, size: Self.p256KeySize)
      let signerKey = try Self.key(type: kSecAttrKeyTypeRSA, size: Self.rsaKeySize)
      let now = Date()
      let tsCaName = DebugTimestampAuthority.encodedName(Self.timestampCaCommonName)
      let tsCaExtensions = [
        Self.extensionField(
          SignOids.crlDistributionPoints,
          critical: false,
          value: Self.distributionPoint(Self.timestampRevocationListAddress)
        ),
        Self.authorityKeyIdentifier(
          Self.keyIdentifier(try Self.ecSubjectPublicKeyInfo(tsCaKey))
        ),
      ]
      let tsAuthority = try DebugTimestampAuthority.make(
        issuerKey: tsCaKey,
        issuerName: tsCaName,
        additionalExtensions: tsCaExtensions
      )
      return Self(
        caCertificate: try Self.issuerCertificate(
          key: issuerKey,
          commonName: Self.caCommonName,
          serial: Self.caSerial,
          at: now
        ),
        caKey: issuerKey,
        timestampCaCertificate: try Self.issuerCertificate(
          key: tsCaKey,
          commonName: Self.timestampCaCommonName,
          serial: Self.timestampCaSerial,
          at: now
        ),
        timestampCaKey: tsCaKey,
        holderCertificate: try Self.signerCertificate(
          key: signerKey, issuerKey: issuerKey, at: now
        ),
        holderKey: signerKey,
        timestampAuthority: tsAuthority
      )
    }

    /// The self-signed CA: basic constraints, certificate and CRL
    /// signing, and its key identifier.
    private static func issuerCertificate(
      key: SecKey,
      commonName: String,
      serial: Int,
      at now: Date
    ) throws -> Data {
      let name = DebugTimestampAuthority.encodedName(commonName)
      let publicKey = try Self.ecSubjectPublicKeyInfo(key)
      return try Self.certificate(
        CertificateFields(
          serial: serial,
          issuer: name,
          subject: name,
          subjectPublicKeyInfo: publicKey,
          extensions: [
            Self.extensionField(
              SignOids.basicConstraints,
              critical: true,
              value: DerEncoder.sequence([DerEncoder.booleanTrue()])
            ),
            Self.extensionField(
              SignOids.keyUsage,
              critical: true,
              value: Self.bitString(
                DerValues.keyUsageCertificateSigningBit | DerValues.keyUsageCrlSigningBit,
                unused: Self.keyUsageUnusedBitsCa
              )
            ),
            Self.subjectKeyIdentifier(publicKey),
          ]
        ),
        signer: key,
        at: now
      )
    }

    /// The card's qualified certificate: non-repudiation, its key
    /// identifiers, and the CA's CRL distribution point.
    private static func signerCertificate(
      key: SecKey,
      issuerKey: SecKey,
      at now: Date
    ) throws -> Data {
      let publicKey = try Self.rsaSubjectPublicKeyInfo(key)
      return try Self.certificate(
        CertificateFields(
          serial: Self.holderSerial,
          issuer: DebugTimestampAuthority.encodedName(Self.caCommonName),
          subject: DebugTimestampAuthority.encodedName(Self.holderCommonName),
          subjectPublicKeyInfo: publicKey,
          extensions: [
            Self.extensionField(
              SignOids.keyUsage,
              critical: true,
              value: Self.bitString(
                Self.nonRepudiationBit,
                unused: Self.keyUsageUnusedBitsNonRepudiation
              )
            ),
            Self.subjectKeyIdentifier(publicKey),
            Self.authorityKeyIdentifier(
              Self.keyIdentifier(try Self.ecSubjectPublicKeyInfo(issuerKey))
            ),
            Self.extensionField(
              SignOids.crlDistributionPoints,
              critical: false,
              value: Self.distributionPoint(Self.revocationListAddress)
            ),
          ]
        ),
        signer: issuerKey,
        at: now
      )
    }

    /// The same authorities, answering time-stamp requests with another
    /// signer certificate issued by the timestamp CA.
    internal func answeringTimestamps(with authority: DebugTimestampAuthority) -> Self {
      Self(
        caCertificate: caCertificate,
        caKey: caKey,
        timestampCaCertificate: timestampCaCertificate,
        timestampCaKey: timestampCaKey,
        holderCertificate: holderCertificate,
        holderKey: holderKey,
        timestampAuthority: authority
      )
    }

    /// The CA's current CRL, issued an hour ago and revoking nothing.
    internal func revocationList() throws -> Data {
      let now = Date()
      let tbs = DerEncoder.sequence([
        DerEncoder.integer(Self.crlVersionTwo),
        DebugTimestampAuthority.ecdsaSha256Algorithm,
        DebugTimestampAuthority.encodedName(Self.caCommonName),
        Self.generalizedTime(now.addingTimeInterval(-Self.revocationListAge)),
        Self.generalizedTime(now.addingTimeInterval(Self.revocationListLifetime)),
        DerEncoder.tlv(
          DerValues.tagContext0Constructed,
          DerEncoder.sequence([
            Self.authorityKeyIdentifier(
              Self.keyIdentifier(try Self.ecSubjectPublicKeyInfo(caKey))
            ),
            Self.extensionField(
              Self.crlNumberOid,
              critical: false,
              value: DerEncoder.integer(Self.revocationListNumber)
            ),
          ])
        ),
      ])
      return DerEncoder.sequence([
        tbs,
        DebugTimestampAuthority.ecdsaSha256Algorithm,
        Self.bitString(try Self.sign(tbs, key: caKey)),
      ])
    }

    /// The timestamp CA's current CRL, issued an hour ago and revoking nothing.
    internal func timestampCaRevocationList() throws -> Data {
      let now = Date()
      let tbs = DerEncoder.sequence([
        DerEncoder.integer(Self.crlVersionTwo),
        DebugTimestampAuthority.ecdsaSha256Algorithm,
        DebugTimestampAuthority.encodedName(Self.timestampCaCommonName),
        Self.generalizedTime(now.addingTimeInterval(-Self.revocationListAge)),
        Self.generalizedTime(now.addingTimeInterval(Self.revocationListLifetime)),
        DerEncoder.tlv(
          DerValues.tagContext0Constructed,
          DerEncoder.sequence([
            Self.authorityKeyIdentifier(
              Self.keyIdentifier(try Self.ecSubjectPublicKeyInfo(timestampCaKey))
            ),
            Self.extensionField(
              Self.crlNumberOid,
              critical: false,
              value: DerEncoder.integer(Self.timestampRevocationListNumber)
            ),
          ])
        ),
      ])
      return DerEncoder.sequence([
        tbs,
        DebugTimestampAuthority.ecdsaSha256Algorithm,
        Self.bitString(try Self.sign(tbs, key: timestampCaKey)),
      ])
    }

    /// The TimeStampResp the generated authority gives to `request`,
    /// over its imprint and echoing its nonce (RFC 3161 section 2.4).
    internal func timestampResponse(to request: Data) throws -> Data? {
      var outer = DerReader(request)
      guard let body = outer.next() else { return nil }
      var fields = DerReader(request, within: body)
      guard
        fields.next() != nil,
        let messageImprint = fields.next()
      else { return nil }
      var imprintFields = DerReader(request, within: messageImprint)
      guard
        imprintFields.next() != nil,
        let hashed = imprintFields.next()
      else { return nil }
      var nonce = Data()
      while let field = fields.next() {
        if field.tag == DerValues.tagInteger {
          nonce = Data(fields.contentData(of: field).drop { $0 == Self.integerSignOctet })
        }
      }
      return try timestampAuthority.response(
        imprint: imprintFields.contentData(of: hashed),
        nonce: nonce,
        generationTime: Self.generalizedTimeText(Date())
      ).response
    }
  }

#endif
