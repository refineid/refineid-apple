// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import Foundation
  import Security

  @testable import CardCore

  /// X.509 construction for the generated test timestamp authority.
  extension DebugTimestampAuthority {
    /// Certificate validity containing the fixed token generation time.
    private static var validity: Data {
      DerEncoder.sequence([
        Self.generalizedTime(Self.notBefore),
        Self.generalizedTime(Self.notAfter),
      ])
    }

    /// Timestamping-only certificate extensions.
    private static var certificateExtensions: [Data] {
      let signatureUsage = UInt8(1) << UInt8(Self.digitalSignatureBitOffset)
      return [
        Self.criticalExtension(
          SignOids.basicConstraints,
          value: DerEncoder.sequence([])
        ),
        Self.criticalExtension(
          SignOids.keyUsage,
          value: DerEncoder.tlv(
            DerValues.tagBitString,
            Data([0, signatureUsage])
          )
        ),
        Self.criticalExtension(
          SignOids.extendedKeyUsage,
          value: DerEncoder.sequence([
            DerEncoder.objectIdentifier(SignOids.timestampingKeyPurpose)
          ])
        ),
      ]
    }

    /// The self-signed X.509 certificate used as the explicit test anchor.
    internal static func certificate(key: SecKey, name: Data) throws -> Data {
      let tbs = DerEncoder.sequence([
        DerEncoder.tlv(
          DerValues.tagContext0Constructed,
          DerEncoder.integer(Self.x509VersionThree)
        ),
        DerEncoder.integer(Self.certificateSerial),
        Self.ecdsaSha256Algorithm,
        name,
        Self.validity,
        name,
        try Self.subjectPublicKeyInfo(key),
        DerEncoder.tlv(
          DerValues.tagContext3Constructed,
          DerEncoder.sequence(Self.certificateExtensions)
        ),
      ])
      let signature = try Self.sign(
        tbs,
        key: key,
        algorithm: .ecdsaSignatureMessageX962SHA256
      )
      return DerEncoder.sequence([
        tbs,
        Self.ecdsaSha256Algorithm,
        Self.bitString(signature),
      ])
    }

    /// X.509 name carrying only a common name.
    internal static func encodedName(_ value: String) -> Data {
      let attribute = DerEncoder.sequence([
        DerEncoder.objectIdentifier(SignOids.commonName),
        DerEncoder.tlv(DerValues.tagUtf8String, Data(value.utf8)),
      ])
      return DerEncoder.sequence([DerEncoder.setOf([attribute])])
    }

    /// SubjectPublicKeyInfo for one generated P-256 public key.
    private static func subjectPublicKeyInfo(_ key: SecKey) throws -> Data {
      guard let publicKey = SecKeyCopyPublicKey(key) else {
        throw Failure.key
      }
      var error: Unmanaged<CFError>?
      guard let copied = SecKeyCopyExternalRepresentation(publicKey, &error)
      else {
        _ = error?.takeRetainedValue()
        throw Failure.key
      }
      return DerEncoder.sequence([
        DerEncoder.sequence([
          DerEncoder.objectIdentifier(Self.ecPublicKeyOid),
          DerEncoder.objectIdentifier(Self.prime256v1Oid),
        ]),
        Self.bitString(copied as Data),
      ])
    }

    /// One critical X.509 extension.
    private static func criticalExtension(
      _ oid: String,
      value: Data
    ) -> Data {
      DerEncoder.sequence([
        DerEncoder.objectIdentifier(oid),
        DerEncoder.booleanTrue(),
        DerEncoder.octetString(value),
      ])
    }

    /// DER GeneralizedTime.
    private static func generalizedTime(_ value: String) -> Data {
      DerEncoder.tlv(DerValues.tagGeneralizedTime, Data(value.utf8))
    }

    /// DER BIT STRING with zero unused bits.
    private static func bitString(_ value: Data) -> Data {
      DerEncoder.tlv(DerValues.tagBitString, Data([0]) + value)
    }
  }

#endif
