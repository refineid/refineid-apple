// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

extension SignerCertificateFixtures {
  /// ASN.1 BIT STRING.
  internal static let bitStringTag: UInt8 = 0x03

  /// ASN.1 BOOLEAN.
  internal static let booleanTag: UInt8 = 0x01

  /// ASN.1 OCTET STRING.
  internal static let octetStringTag: UInt8 = 0x04

  /// ASN.1 GeneralizedTime.
  internal static let generalizedTimeTag: UInt8 = 0x18

  /// ASN.1 NULL.
  internal static let nullTag: UInt8 = 0x05

  /// ASN.1 UTF8String.
  internal static let utf8StringTag: UInt8 = 0x0C

  /// Explicit context tag for the X.509 version.
  internal static let versionTag: UInt8 = 0xA0

  /// Explicit context tag for X.509 extensions.
  internal static let extensionsTag: UInt8 = 0xA3

  /// DER BOOLEAN TRUE.
  internal static let booleanTrue: UInt8 = 0xFF

  /// id-at-commonName.
  internal static let commonNameOid = "2.5.4.3"

  /// id-ce-basicConstraints.
  internal static let basicConstraintsOid = "2.5.29.19"

  /// id-ce-keyUsage.
  internal static let keyUsageOid = "2.5.29.15"

  /// ecdsa-with-SHA512.
  internal static let ecdsaSha512Oid = "1.2.840.10045.4.3.4"

  /// ecdsa-with-SHA256.
  internal static let ecdsaSha256Oid = "1.2.840.10045.4.3.2"

  /// sha256WithRSAEncryption.
  internal static let rsaSha256Oid = "1.2.840.113549.1.1.11"

  /// P-256 key size.
  internal static let ecdsaP256KeySize = 256

  /// P-521 key size.
  internal static let ecdsaP521KeySize = 521

  /// RSA fixture key size.
  internal static let rsaKeySize = 2_048

  /// X.509 version 3's zero-based value.
  internal static let versionThree = 2

  /// KeyUsage's keyEncipherment bit position from the high end.
  internal static let keyEnciphermentBitOffset = 3
}
