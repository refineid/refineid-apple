// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CryptoKit
  import Foundation
  import Security
  import Testing

  @testable import CardCore

  /// OCSP responses the issuing CA signs over the signer (RFC 6960
  /// section 4.2.1).
  extension DocumentTrustFixture {
    /// A CertID field minted to name something other than the signer.
    internal enum CertIdMismatch: CaseIterable {
      case issuerName
      case issuerKey
      case serial
    }

    /// The CertID hash algorithm of a minted response.
    internal enum CertIdHash {
      case sha1
      case sha256
    }

    /// Bytes no certificate field holds.
    private static let otherBytes = Data("another".utf8)

    /// The responses' producedAt and thisUpdate.
    internal static let ocspProducedAt = "20260501000000Z"

    /// The responses' nextUpdate.
    private static let ocspNextUpdate = "20260901000000Z"

    /// OCSPResponseStatus successful.
    private static let successfulStatus = 0

    /// `data` hashed under `hash`.
    private static func digest(_ data: Data, _ hash: CertIdHash) -> Data {
      switch hash {
      case .sha1:
        Data(Insecure.SHA1.hash(data: data))

      case .sha256:
        Data(SHA256.hash(data: data))
      }
    }

    /// One DER GeneralizedTime.
    private static func time(_ value: String) -> Data {
      DerEncoder.tlv(DerValues.tagGeneralizedTime, Data(value.utf8))
    }

    /// A good answer for the signer, its CertID hashed under `hash`.
    internal func ocspResponse(certIdHash hash: CertIdHash) throws -> Data {
      try self.ocspResponse(certIdHash: hash, mismatching: nil)
    }

    /// A good answer whose CertID names something else in `mismatching`.
    internal func ocspResponse(
      certIdHash hash: CertIdHash,
      mismatching: CertIdMismatch?
    ) throws -> Data {
      let target = try #require(CertificateFacts(der: signer.certificate))
      let issuer = try #require(CertificateFacts(der: issuing))
      let oid = hash == .sha1 ? SignOids.sha1 : SignOids.sha256
      let certId = DerEncoder.sequence([
        DerEncoder.sequence([DerEncoder.objectIdentifier(oid), DerEncoder.null()]),
        DerEncoder.octetString(
          Self.digest(mismatching == .issuerName ? Self.otherBytes : target.issuerName, hash)),
        DerEncoder.octetString(
          Self.digest(mismatching == .issuerKey ? Self.otherBytes : issuer.publicKeyBits, hash)),
        DerEncoder.unsignedInteger(mismatching == .serial ? Self.otherBytes : signerSerial),
      ])
      let single = DerEncoder.sequence([
        certId,
        DerEncoder.tlv(DerValues.tagContext0Primitive, Data()),
        Self.time(Self.ocspProducedAt),
        DerEncoder.tlv(DerValues.tagContext0Constructed, Self.time(Self.ocspNextUpdate)),
      ])
      let responseData = DerEncoder.sequence([
        DerEncoder.tlv(DerValues.tagContext1Constructed, issuer.subjectName),
        Self.time(Self.ocspProducedAt),
        DerEncoder.sequence([single]),
      ])
      let (algorithm, signature) = try self.issuerSignature(over: responseData)
      let basic = DerEncoder.sequence([
        responseData,
        algorithm,
        DerEncoder.tlv(DerValues.tagBitString, Data([0]) + signature),
      ])
      return DerEncoder.sequence([
        DerEncoder.tlv(DerValues.tagEnumerated, Data([UInt8(Self.successfulStatus)])),
        DerEncoder.tlv(
          DerValues.tagContext0Constructed,
          DerEncoder.sequence([
            DerEncoder.objectIdentifier(SignOids.ocspBasic),
            DerEncoder.octetString(basic),
          ])),
      ])
    }

    /// The issuing CA's signature over `data`.
    private func issuerSignature(over data: Data) throws -> (algorithm: Data, value: Data) {
      let algorithm: Data
      let secAlgorithm: SecKeyAlgorithm
      if kind == .rsaSha256 {
        algorithm = DerEncoder.sequence([
          DerEncoder.objectIdentifier(SignOids.sha256WithRsa), DerEncoder.null(),
        ])
        secAlgorithm = .rsaSignatureMessagePKCS1v15SHA256
      } else {
        algorithm = DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.ecdsaWithSha256)])
        secAlgorithm = .ecdsaSignatureMessageX962SHA256
      }
      var error: Unmanaged<CFError>?
      let value = try #require(
        SecKeyCreateSignature(issuingKey, secAlgorithm, data as CFData, &error) as Data?)
      return (algorithm, value)
    }

  }

#endif
