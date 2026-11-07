// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security
import Testing

@testable import CardCore

/// Verifying a list signature under the signer certificate's key.
@Suite
internal struct XmlSignatureMethodTests {
  /// rsaEncryption (RFC 8017 appendix A.1).
  private static let rsaEncryptionOid = "1.2.840.113549.1.1.1"

  /// id-RSASSA-PSS (RFC 4055 section 3.1), of the same encoded length.
  private static let rsaPssOid = "1.2.840.113549.1.1.10"

  /// The signed message.
  private static let message = Data("canonical signed info".utf8)

  /// The serial of the test certificate.
  private static let serial = Data("p".utf8)

  /// A certificate of `key` whose SubjectPublicKeyInfo names
  /// id-RSASSA-PSS, as the German list signer's does.
  ///
  /// The certificate's own signature is not what is tested, and its
  /// edited bytes no longer verify.
  private static func pssCertificate(key: SecKey) throws -> Data {
    let commonName = "RefineID PSS List Signer"
    let certificate = try CertificateRevocationListFixtures.certificate(
      description: .init(
        allowsCrlSigning: false, includesKeyUsage: true, malformedKeyUsage: false,
        commonName: commonName, isCertificateAuthority: false,
        issuerName: CertificateRevocationListFixtures.name(commonName), serial: Self.serial),
      publicKey: key, signer: key, kind: .rsaSha256)
    let rsaEncryption = DerEncoder.objectIdentifier(Self.rsaEncryptionOid)
    let pss = DerEncoder.objectIdentifier(Self.rsaPssOid)
    let range = try #require(certificate.range(of: rsaEncryption))
    return certificate.replacingOccurrences(in: range, with: pss)
  }

  @Test
  internal func aPssSignatureVerifiesUnderAnRsassaPssKey() throws {
    let key = try CertificateRevocationListFixtures.makeKey(for: .rsaSha256)
    let certificate = try Self.pssCertificate(key: key)
    var error: Unmanaged<CFError>?
    let signature = try #require(
      SecKeyCreateSignature(
        key, .rsaSignatureMessagePSSSHA256, Self.message as CFData, &error) as Data?)
    #expect(
      XmlSignatureMethod.rsaPssSha256.verifies(
        signature, over: Self.message, certificate: certificate))
    #expect(
      !XmlSignatureMethod.rsaPssSha256.verifies(
        signature, over: Data("another message".utf8), certificate: certificate))
    #expect(
      !XmlSignatureMethod.rsaSha512.verifies(
        signature, over: Self.message, certificate: certificate))
  }
}

extension Data {
  /// These bytes with `range` replaced by `replacement`.
  fileprivate func replacingOccurrences(in range: Range<Index>, with replacement: Data) -> Data {
    var copy = self
    copy.replaceSubrange(range, with: replacement)
    return copy
  }
}
