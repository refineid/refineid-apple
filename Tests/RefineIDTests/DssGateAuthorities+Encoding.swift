// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import CryptoKit
  import Foundation
  import Security

  @testable import CardCore

  /// DER construction for the DSS gate's synthetic authorities.
  extension DssGateAuthorities {
    /// What one certificate says about itself.
    internal struct CertificateFields {
      internal let serial: Int
      internal let issuer: Data
      internal let subject: Data
      internal let subjectPublicKeyInfo: Data
      internal let extensions: [Data]
    }

    internal static let crlNumberOid = "2.5.29.20"
    private static let authorityKeyIdentifierOid = "2.5.29.35"
    private static let ecPublicKeyOid = "1.2.840.10045.2.1"
    private static let prime256v1Oid = "1.2.840.10045.3.1.7"
    private static let generalizedTimeFormat = "yyyyMMddHHmmss'Z'"
    private static let posixLocale = "en_US_POSIX"

    /// A generated key of `type` and `size` bits.
    internal static func key(type: CFString, size: Int) throws -> SecKey {
      let attributes: [CFString: Any] = [
        kSecAttrKeyType: type,
        kSecAttrKeySizeInBits: size,
      ]
      var error: Unmanaged<CFError>?
      guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
        _ = error?.takeRetainedValue()
        throw Failure.key
      }
      return key
    }

    /// The SubjectPublicKeyInfo of a P-256 key.
    internal static func ecSubjectPublicKeyInfo(_ key: SecKey) throws -> Data {
      DerEncoder.sequence([
        DerEncoder.sequence([
          DerEncoder.objectIdentifier(Self.ecPublicKeyOid),
          DerEncoder.objectIdentifier(Self.prime256v1Oid),
        ]),
        Self.bitString(try Self.publicKeyBytes(key)),
      ])
    }

    /// The SubjectPublicKeyInfo of an RSA key.
    internal static func rsaSubjectPublicKeyInfo(_ key: SecKey) throws -> Data {
      DerEncoder.sequence([
        DerEncoder.sequence([
          DerEncoder.objectIdentifier(SignOids.rsaEncryption),
          DerEncoder.null(),
        ]),
        Self.bitString(try Self.publicKeyBytes(key)),
      ])
    }

    /// The SHA-1 of the subject public key bits (RFC 5280 section
    /// 4.2.1.2, method 1).
    internal static func keyIdentifier(_ subjectPublicKeyInfo: Data) -> Data {
      var outer = DerReader(subjectPublicKeyInfo)
      guard let info = outer.next() else { return Data() }
      var fields = DerReader(subjectPublicKeyInfo, within: info)
      _ = fields.next()
      guard let bits = fields.next() else { return Data() }
      return Data(Insecure.SHA1.hash(data: fields.contentData(of: bits).dropFirst()))
    }

    /// An X.509 v3 certificate of `fields`, signed with ECDSA-SHA256.
    internal static func certificate(
      _ fields: CertificateFields,
      signer: SecKey,
      at now: Date
    ) throws -> Data {
      let tbs = DerEncoder.sequence([
        DerEncoder.tlv(
          DerValues.tagContext0Constructed,
          DerEncoder.integer(Int(DerValues.certificateVersionThree))
        ),
        DerEncoder.integer(fields.serial),
        DebugTimestampAuthority.ecdsaSha256Algorithm,
        fields.issuer,
        DerEncoder.sequence([
          Self.generalizedTime(now.addingTimeInterval(-Self.validityMargin)),
          Self.generalizedTime(now.addingTimeInterval(Self.validityMargin)),
        ]),
        fields.subject,
        fields.subjectPublicKeyInfo,
        DerEncoder.tlv(
          DerValues.tagContext3Constructed, DerEncoder.sequence(fields.extensions)
        ),
      ])
      return DerEncoder.sequence([
        tbs,
        DebugTimestampAuthority.ecdsaSha256Algorithm,
        Self.bitString(try Self.sign(tbs, key: signer)),
      ])
    }

    /// One ECDSA-SHA256 signature by `key`.
    internal static func sign(_ value: Data, key: SecKey) throws -> Data {
      do {
        return try DebugTimestampAuthority.sign(
          value, key: key, algorithm: .ecdsaSignatureMessageX962SHA256
        )
      } catch {
        throw Failure.signature
      }
    }

    /// One X.509 extension.
    internal static func extensionField(_ oid: String, critical: Bool, value: Data) -> Data {
      var fields = [DerEncoder.objectIdentifier(oid)]
      if critical { fields.append(DerEncoder.booleanTrue()) }
      fields.append(DerEncoder.octetString(value))
      return DerEncoder.sequence(fields)
    }

    /// The `subjectKeyIdentifier` of a public key.
    internal static func subjectKeyIdentifier(_ subjectPublicKeyInfo: Data) -> Data {
      Self.extensionField(
        SignOids.subjectKeyIdentifier,
        critical: false,
        value: DerEncoder.octetString(Self.keyIdentifier(subjectPublicKeyInfo))
      )
    }

    /// The `authorityKeyIdentifier` naming `identifier`.
    internal static func authorityKeyIdentifier(_ identifier: Data) -> Data {
      Self.extensionField(
        Self.authorityKeyIdentifierOid,
        critical: false,
        value: DerEncoder.sequence([
          DerEncoder.tlv(DerValues.tagContext0Primitive, identifier)
        ])
      )
    }

    /// One `DistributionPoint` naming `address` by its full name
    /// (RFC 5280 section 4.2.1.13).
    internal static func distributionPoint(_ address: String) -> Data {
      DerEncoder.sequence([
        DerEncoder.sequence([
          DerEncoder.tlv(
            DerValues.tagContext0Constructed,
            DerEncoder.tlv(
              DerValues.tagContext0Constructed,
              DerEncoder.tlv(DerValues.tagContext6Primitive, Data(address.utf8))
            )
          )
        ])
      ])
    }

    /// `instant` as GeneralizedTime text, in UTC to the second.
    internal static func generalizedTimeText(_ instant: Date) -> String {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: Self.posixLocale)
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = Self.generalizedTimeFormat
      return formatter.string(from: instant)
    }

    /// DER GeneralizedTime.
    internal static func generalizedTime(_ instant: Date) -> Data {
      DerEncoder.tlv(
        DerValues.tagGeneralizedTime, Data(Self.generalizedTimeText(instant).utf8)
      )
    }

    /// A BIT STRING with no unused bits.
    internal static func bitString(_ value: Data) -> Data {
      DerEncoder.tlv(DerValues.tagBitString, Data([DerValues.bitStringNoUnusedBits]) + value)
    }

    /// A one-octet named-bit BIT STRING.
    internal static func bitString(_ bits: UInt8, unused: UInt8) -> Data {
      DerEncoder.tlv(DerValues.tagBitString, Data([unused, bits]))
    }

    private static func publicKeyBytes(_ key: SecKey) throws -> Data {
      guard let publicKey = SecKeyCopyPublicKey(key) else { throw Failure.key }
      var error: Unmanaged<CFError>?
      guard let copied = SecKeyCopyExternalRepresentation(publicKey, &error) else {
        _ = error?.takeRetainedValue()
        throw Failure.key
      }
      return copied as Data
    }
  }

#endif
