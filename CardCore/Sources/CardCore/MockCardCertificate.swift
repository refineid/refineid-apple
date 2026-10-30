// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security

/// Creates and primes synthetic mock identity cards and valid X.509 certificates
/// for local testing, simulator qualification, and developer demonstrations.
public enum MockCardCertificate {
  // MARK: Static Properties

  private static let commonNameOid = "2.5.4.3"
  private static let basicConstraintsOid = "2.5.29.19"
  private static let keyUsageOid = "2.5.29.15"
  private static let ecdsaSha256Oid = "1.2.840.10045.4.3.2"
  private static let ecPublicKeyOid = "1.2.840.10045.2.1"
  private static let secp256r1Oid = "1.2.840.10045.3.1.7"
  private static let x509V3Version = 2
  @usableFromInline internal static let defaultSerialNumber = 1
  private static let tagContextSpecific0: UInt8 = 160
  private static let tagContextSpecific3: UInt8 = 163
  private static let tagUtf8String: UInt8 = 12
  private static let tagGeneralizedTime: UInt8 = 24
  private static let tagBitString: UInt8 = 3
  private static let tagBoolean: UInt8 = 1
  private static let tagOctetString: UInt8 = 4
  private static let booleanTrueByte: UInt8 = 255
  private static let unusedBitsZeroByte: UInt8 = 0
  private static let digitalSignatureKeyUsageByte: UInt8 = 128
  private static let defaultAtrByte1: UInt8 = 59
  private static let defaultAtrByte2: UInt8 = 128
  private static let defaultAtrByte3: UInt8 = 1
  private static let defaultAtr = Data([
    defaultAtrByte1, defaultAtrByte2, defaultAtrByte2, defaultAtrByte3, defaultAtrByte3,
  ])

  // MARK: Static Functions

  /// Generates a valid self-signed P-256 ECDSA X.509 certificate DER.
  public static func makeCertificate(
    commonName: String = "DOE JANE 12345678N",
    serialNumber: Int = defaultSerialNumber
  ) throws -> Data {
    let privateKey = P256.Signing.PrivateKey()
    let publicKeyBytes = privateKey.publicKey.x963Representation
    let sigAlg = DerEncoder.sequence([DerEncoder.objectIdentifier(ecdsaSha256Oid)])
    let tbsCertificate = buildTbsCertificate(
      publicKeyBytes: publicKeyBytes,
      commonName: commonName,
      serialNumber: serialNumber,
      sigAlg: sigAlg
    )
    let signature = try privateKey.signature(for: tbsCertificate)
    let derSignature = signature.derRepresentation
    return DerEncoder.sequence([
      tbsCertificate,
      sigAlg,
      DerEncoder.tlv(tagBitString, Data([unusedBitsZeroByte]) + derSignature),
    ])
  }

  private static func buildTbsCertificate(
    publicKeyBytes: Data,
    commonName: String,
    serialNumber: Int,
    sigAlg: Data
  ) -> Data {
    let version = DerEncoder.tlv(tagContextSpecific0, DerEncoder.integer(x509V3Version))
    let serial = DerEncoder.integer(serialNumber)
    let name = DerEncoder.sequence([
      DerEncoder.setOf([
        DerEncoder.sequence([
          DerEncoder.objectIdentifier(commonNameOid),
          DerEncoder.tlv(tagUtf8String, Data(commonName.utf8)),
        ])
      ])
    ])
    let validity = DerEncoder.sequence([
      DerEncoder.tlv(tagGeneralizedTime, Data("20250101000000Z".utf8)),
      DerEncoder.tlv(tagGeneralizedTime, Data("20350101000000Z".utf8)),
    ])
    let subjectPublicKeyInfo = DerEncoder.sequence([
      DerEncoder.sequence([
        DerEncoder.objectIdentifier(ecPublicKeyOid),
        DerEncoder.objectIdentifier(secp256r1Oid),
      ]),
      DerEncoder.tlv(tagBitString, Data([unusedBitsZeroByte]) + publicKeyBytes),
    ])
    let basicConstraints = DerEncoder.sequence([
      DerEncoder.objectIdentifier(basicConstraintsOid),
      DerEncoder.tlv(tagBoolean, Data([booleanTrueByte])),
      DerEncoder.tlv(tagOctetString, DerEncoder.sequence([])),
    ])
    let keyUsage = DerEncoder.sequence([
      DerEncoder.objectIdentifier(keyUsageOid),
      DerEncoder.tlv(tagBoolean, Data([booleanTrueByte])),
      DerEncoder.tlv(
        tagOctetString,
        DerEncoder.tlv(tagBitString, Data([unusedBitsZeroByte, digitalSignatureKeyUsageByte]))
      ),
    ])
    let extensions = DerEncoder.tlv(
      tagContextSpecific3,
      DerEncoder.sequence([basicConstraints, keyUsage])
    )
    return DerEncoder.sequence([
      version,
      serial,
      sigAlg,
      name,
      validity,
      name,
      subjectPublicKeyInfo,
      extensions,
    ])
  }

  /// Primes a synthetic identity into the device's PrimeStore and CardCredentialStore.
  @discardableResult
  public static func primeSyntheticIdentity(
    can: String = "123456",
    holderName: String = "DOE JANE 12345678N",
    chipSerial: ChipSerial? = ChipSerial(value: "XA1234567"),
    certificate: Data? = nil
  ) -> Bool {
    do {
      let certDER = try certificate ?? makeCertificate(commonName: holderName)
      guard
        let identity = PrimedIdentity(
          can: can,
          certificate: certDER,
          issuer: nil,
          chipSerial: chipSerial,
          activationCheck: .passed
        ),
        let lookupID = PrimeLookupIdentifier(answerToReset: defaultAtr)
      else {
        return false
      }
      CardCredentialStore.save(cardAccessNumber: can)
      return PrimeStore.store(identity, forLookup: lookupID)
    } catch {
      return false
    }
  }
}
