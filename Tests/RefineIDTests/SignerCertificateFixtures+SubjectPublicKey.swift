// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

extension SignerCertificateFixtures {
  /// ASN.1 NULL.
  private static let spkiNullTag: UInt8 = 0x05

  /// id-ecPublicKey.
  private static let spkiEcPublicKeyOid = "1.2.840.10045.2.1"

  /// rsaEncryption.
  private static let spkiRsaEncryptionOid = "1.2.840.113549.1.1.1"

  /// id-RSASSA-PSS.
  private static let spkiRsaPssOid = "1.2.840.113549.1.1.10"

  /// secp521r1.
  private static let spkiSecp521r1Oid = "1.3.132.0.35"

  /// secp256r1.
  private static let spkiSecp256r1Oid = "1.2.840.10045.3.1.7"

  /// AlgorithmIdentifier for a controlled SubjectPublicKeyInfo profile.
  internal static func subjectPublicKeyAlgorithm(
    kind: KeyKind,
    profile: SubjectPublicKeyProfile
  ) throws -> Data {
    switch (kind, profile) {
    case (.ecdsaP256, .rsaEncryption):
      return DerEncoder.sequence([
        DerEncoder.objectIdentifier(Self.spkiEcPublicKeyOid),
        DerEncoder.objectIdentifier(Self.spkiSecp256r1Oid),
      ])

    case (.ecdsaP521, .rsaEncryption):
      return DerEncoder.sequence([
        DerEncoder.objectIdentifier(Self.spkiEcPublicKeyOid),
        DerEncoder.objectIdentifier(Self.spkiSecp521r1Oid),
      ])

    case (.rsa, .rsaEncryption):
      return DerEncoder.sequence([
        DerEncoder.objectIdentifier(Self.spkiRsaEncryptionOid),
        DerEncoder.tlv(Self.spkiNullTag, Data()),
      ])

    case (.rsa, .rsaPssAbsentParameters), (.rsa, .rsaPssUnusedBits):
      return DerEncoder.sequence([
        DerEncoder.objectIdentifier(Self.spkiRsaPssOid)
      ])

    case (.rsa, .rsaPssEmptyParameters):
      return DerEncoder.sequence([
        DerEncoder.objectIdentifier(Self.spkiRsaPssOid),
        DerEncoder.sequence([]),
      ])

    case (.rsa, .rsaPssIntegerParameter):
      return DerEncoder.sequence([
        DerEncoder.objectIdentifier(Self.spkiRsaPssOid),
        DerEncoder.integer(0),
      ])

    case (.rsa, .rsaPssNullParameters):
      return DerEncoder.sequence([
        DerEncoder.objectIdentifier(Self.spkiRsaPssOid),
        DerEncoder.tlv(Self.spkiNullTag, Data()),
      ])

    default:
      throw Failure.keyCreation
    }
  }
}
