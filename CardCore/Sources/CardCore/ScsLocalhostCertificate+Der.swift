// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension ScsLocalhostCertificate {
  internal static func distinguishedName(commonName: String) -> Data {
    let attribute = DerEncoder.sequence([
      DerEncoder.objectIdentifier(SignOids.commonName),
      DerEncoder.tlv(DerValues.tagUtf8String, Data(commonName.utf8)),
    ])
    return DerEncoder.sequence([DerEncoder.setOf([attribute])])
  }

  internal static func signedCertificate(tbs: Data, signature: Data) -> Data {
    var bits = Data([DerValues.bitStringNoUnusedBits])
    bits.append(signature)
    return DerEncoder.sequence([
      tbs,
      signatureAlgorithm,
      DerEncoder.tlv(DerValues.tagBitString, bits),
    ])
  }

  internal static func tbsCertificate(_ fields: TbsFields) -> Data {
    let validity = DerEncoder.sequence([
      rfc5280Time(fields.notBefore),
      rfc5280Time(fields.notAfter),
    ])
    return DerEncoder.sequence([
      DerEncoder.tlv(
        DerValues.tagContext0Constructed,
        DerEncoder.integer(Int(DerValues.certificateVersionThree))
      ),
      DerEncoder.unsignedInteger(fields.serialNumber),
      signatureAlgorithm,
      fields.issuer,
      validity,
      fields.subject,
      fields.subjectPublicKeyInfo,
      DerEncoder.tlv(DerValues.tagContext3Constructed, fields.extensions),
    ])
  }

  internal static func rootExtensions(subjectKeyId: Data) -> Data {
    let basicConstraints = extensionRecord(
      oid: SignOids.basicConstraints,
      critical: true,
      value: DerEncoder.sequence([DerEncoder.booleanTrue(), DerEncoder.integer(0)])
    )
    let keyUsage = extensionRecord(
      oid: SignOids.keyUsage,
      critical: true,
      value: DerEncoder.tlv(
        DerValues.tagBitString,
        Data([ScsValues.rootKeyUsageUnusedBits, ScsValues.rootKeyUsageBits])
      )
    )
    let subjectKeyIdentifier = extensionRecord(
      oid: SignOids.subjectKeyIdentifier,
      critical: false,
      value: DerEncoder.octetString(subjectKeyId)
    )
    let permitted = DerEncoder.tlv(
      DerValues.tagContext0Constructed,
      DerEncoder.sequence([
        DerEncoder.tlv(DerValues.tagContext2Primitive, Data("localhost".utf8))
      ])
        + DerEncoder.sequence([
          DerEncoder.tlv(DerValues.tagContext7Primitive, Data(ScsValues.loopbackNameConstraint))
        ])
        + DerEncoder.sequence([
          DerEncoder.tlv(DerValues.tagContext7Primitive, Data(ScsValues.ipv6LoopbackNameConstraint))
        ])
    )
    let nameConstraints = extensionRecord(
      oid: SignOids.nameConstraints,
      critical: true,
      value: DerEncoder.sequence([permitted])
    )
    return DerEncoder.sequence([
      basicConstraints,
      keyUsage,
      subjectKeyIdentifier,
      nameConstraints,
    ])
  }

  internal static func leafExtensions(subjectKeyId: Data, authorityKeyId: Data) -> Data {
    let basicConstraints = extensionRecord(
      oid: SignOids.basicConstraints,
      critical: true,
      value: DerEncoder.sequence([])
    )
    let keyUsage = extensionRecord(
      oid: SignOids.keyUsage,
      critical: true,
      value: DerEncoder.tlv(
        DerValues.tagBitString,
        Data([ScsValues.serverKeyUsageUnusedBits, ScsValues.serverKeyUsageBits])
      )
    )
    let extendedKeyUsage = extensionRecord(
      oid: SignOids.extendedKeyUsage,
      critical: false,
      value: DerEncoder.sequence([
        DerEncoder.objectIdentifier(SignOids.serverAuthentication)
      ])
    )
    let subjectKeyIdentifier = extensionRecord(
      oid: SignOids.subjectKeyIdentifier,
      critical: false,
      value: DerEncoder.octetString(subjectKeyId)
    )
    let authorityKeyIdentifier = extensionRecord(
      oid: SignOids.authorityKeyIdentifier,
      critical: false,
      value: DerEncoder.sequence([
        DerEncoder.tlv(DerValues.tagContext0Primitive, authorityKeyId)
      ])
    )
    let alternativeNames = extensionRecord(
      oid: SignOids.subjectAltName,
      critical: false,
      value: DerEncoder.sequence([
        DerEncoder.tlv(DerValues.tagContext2Primitive, Data("localhost".utf8)),
        DerEncoder.tlv(DerValues.tagContext7Primitive, Data(ScsValues.loopbackAddress)),
      ])
    )
    return DerEncoder.sequence([
      basicConstraints,
      keyUsage,
      extendedKeyUsage,
      subjectKeyIdentifier,
      authorityKeyIdentifier,
      alternativeNames,
    ])
  }

  internal static func randomSerial() -> Data {
    var bytes = (0..<ScsValues.serialOctetCount).map { _ in UInt8.random(in: .min ... .max) }
    bytes[0] &= ScsValues.serialPositiveMask
    if bytes.allSatisfy({ $0 == 0 }) {
      bytes[bytes.count - 1] = ScsValues.serialNonZeroBit
    }
    return Data(bytes)
  }

  private static func extensionRecord(oid: String, critical: Bool, value: Data) -> Data {
    var elements = [DerEncoder.objectIdentifier(oid)]
    if critical {
      elements.append(DerEncoder.booleanTrue())
    }
    elements.append(DerEncoder.octetString(value))
    return DerEncoder.sequence(elements)
  }

  private static func rfc5280Time(_ date: Date) -> Data {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let year = utc.component(.year, from: date)
    let formatter = DateFormatter()
    formatter.timeZone = utc.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    if year >= ScsValues.generalizedTimeCutoffYear {
      formatter.dateFormat = "yyyyMMddHHmmss'Z'"
      return DerEncoder.tlv(DerValues.tagGeneralizedTime, Data(formatter.string(from: date).utf8))
    }
    formatter.dateFormat = "yyMMddHHmmss'Z'"
    return DerEncoder.tlv(DerValues.tagUtcTime, Data(formatter.string(from: date).utf8))
  }
}
