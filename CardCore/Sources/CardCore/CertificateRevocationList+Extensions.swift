// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension CertificateRevocationList {
  /// id-ce-cRLNumber (RFC 5280 section 5.2.3).
  private static let crlNumberOid = "2.5.29.20"

  /// id-ce-cRLReasons (RFC 5280 section 5.3.1).
  private static let reasonCodeOid = "2.5.29.21"

  /// id-ce-invalidityDate (RFC 5280 section 5.3.2).
  private static let invalidityDateOid = "2.5.29.24"

  /// id-ce-deltaCRLIndicator (RFC 5280 section 5.2.4).
  private static let deltaCrlIndicatorOid = "2.5.29.27"

  /// id-ce-issuingDistributionPoint (RFC 5280 section 5.2.5).
  private static let issuingDistributionPointOid = "2.5.29.28"

  /// id-ce-certificateIssuer (RFC 5280 section 5.3.3).
  private static let certificateIssuerOid = "2.5.29.29"

  /// id-ce-authorityKeyIdentifier (RFC 5280 section 5.2.1).
  private static let authorityKeyIdentifierOid = "2.5.29.35"

  /// id-ce-freshestCRL (RFC 5280 section 5.2.6).
  private static let freshestCrlOid = "2.5.29.46"

  /// The difference between primitive and constructed context tags.
  private static let constructedTagBit =
    DerValues.tagContext0Constructed - DerValues.tagContext0Primitive

  /// Context-specific primitive tag `[3]` in IssuingDistributionPoint.
  private static let tagContext3Primitive =
    DerValues.tagContext3Constructed - Self.constructedTagBit

  /// Context-specific primitive tag `[4]` in IssuingDistributionPoint.
  private static let tagContext4Primitive =
    DerValues.tagContext4Constructed - Self.constructedTagBit

  /// Context-specific primitive tag `[5]` in IssuingDistributionPoint.
  private static let tagContext5Primitive = Self.tagContext4Primitive + 1

  /// Largest unused-bit count representable by a BIT STRING first octet.
  private static let maximumUnusedBitCount = UInt8.bitWidth - 1

  /// Enforces complete-list semantics on CRL-wide extensions.
  internal static func parseCrlExtensions(
    _ encoded: Data,
    wrapper: DerReader.Element
  ) throws {
    var wrapperReader = DerReader(encoded, within: wrapper)
    let sequence = try Self.requiredElement(
      from: &wrapperReader,
      in: encoded,
      tag: DerValues.tagSequence
    )
    guard wrapperReader.isAtEnd else { throw ValidationFailure.malformed }
    for extensionValue in try Self.extensions(in: encoded, sequence: sequence) {
      try Self.validateCrlExtension(extensionValue)
    }
  }

  /// Applies the supported semantics for one CRL-wide extension.
  private static func validateCrlExtension(
    _ extensionValue: ExtensionValue
  ) throws {
    switch extensionValue.identifier {
    case DerEncoder.objectIdentifier(Self.deltaCrlIndicatorOid):
      throw ValidationFailure.deltaUnsupported

    case DerEncoder.objectIdentifier(Self.issuingDistributionPointOid):
      try Self.parseIssuingDistributionPoint(extensionValue.value)

    case DerEncoder.objectIdentifier(Self.crlNumberOid):
      _ = try Self.onlyUnsignedInteger(in: extensionValue.value)
      try Self.rejectCritical(extensionValue)

    case DerEncoder.objectIdentifier(Self.authorityKeyIdentifierOid),
      DerEncoder.objectIdentifier(Self.freshestCrlOid):
      try Self.rejectCritical(extensionValue)

    default:
      try Self.rejectCritical(extensionValue)
    }
  }

  /// Rejects entry-level certificateIssuer and unsupported critical
  /// semantics, and answers the entry's reasonCode.
  internal static func parseEntryExtensions(
    _ encoded: Data,
    sequence: DerReader.Element
  ) throws -> RevocationReason? {
    var reason: RevocationReason?
    for extensionValue in try Self.extensions(in: encoded, sequence: sequence) {
      if let entryReason = try Self.validateEntryExtension(extensionValue) {
        reason = entryReason
      }
    }
    return reason
  }

  /// Applies the supported semantics for one CRL-entry extension and
  /// answers the reason a reasonCode names.
  private static func validateEntryExtension(
    _ extensionValue: ExtensionValue
  ) throws -> RevocationReason? {
    switch extensionValue.identifier {
    case DerEncoder.objectIdentifier(Self.certificateIssuerOid):
      throw ValidationFailure.indirectUnsupported

    case DerEncoder.objectIdentifier(Self.reasonCodeOid):
      let code = try Self.onlyElement(
        in: extensionValue.value,
        tag: DerValues.tagEnumerated
      )
      try Self.rejectCritical(extensionValue)
      return DerReader(extensionValue.value).integerValue(of: code)
        .map(RevocationReason.init(code:)) ?? .unrecognized

    case DerEncoder.objectIdentifier(Self.invalidityDateOid):
      let date = try Self.onlyElement(
        in: extensionValue.value,
        tag: DerValues.tagGeneralizedTime
      )
      _ = try Self.time(in: extensionValue.value, element: date)
      try Self.rejectCritical(extensionValue)
      return nil

    default:
      try Self.rejectCritical(extensionValue)
      return nil
    }
  }

  /// Parses an Extensions sequence and rejects duplicate identifiers.
  private static func extensions(
    in encoded: Data,
    sequence: DerReader.Element
  ) throws -> [ExtensionValue] {
    var reader = DerReader(encoded, within: sequence)
    var values: [ExtensionValue] = []
    var identifiers = Set<Data>()
    while let element = try Self.nextElement(from: &reader, in: encoded) {
      values.append(
        try Self.extensionValue(
          in: encoded,
          element: element,
          identifiers: &identifiers
        )
      )
    }
    guard reader.isAtEnd, !values.isEmpty else {
      throw ValidationFailure.malformed
    }
    return values
  }

  /// Parses one Extension and records its unique identifier.
  private static func extensionValue(
    in encoded: Data,
    element: DerReader.Element,
    identifiers: inout Set<Data>
  ) throws -> ExtensionValue {
    guard element.tag == DerValues.tagSequence else {
      throw ValidationFailure.malformed
    }
    var reader = DerReader(encoded, within: element)
    let identifier = try Self.requiredElement(
      from: &reader,
      in: encoded,
      tag: DerValues.tagObjectIdentifier
    )
    let identifierData = reader.data(of: identifier)
    guard identifiers.insert(identifierData).inserted else {
      throw ValidationFailure.malformed
    }
    var value = try Self.requiredElement(from: &reader, in: encoded)
    let isCritical = try Self.consumeCriticalFlag(
      value: &value,
      reader: &reader,
      encoded: encoded
    )
    guard value.tag == DerValues.tagOctetString, reader.isAtEnd else {
      throw ValidationFailure.malformed
    }
    return ExtensionValue(
      identifier: identifierData,
      isCritical: isCritical,
      value: reader.contentData(of: value)
    )
  }

  /// Consumes an optional DER TRUE critical flag and advances to extnValue.
  private static func consumeCriticalFlag(
    value: inout DerReader.Element,
    reader: inout DerReader,
    encoded: Data
  ) throws -> Bool {
    guard value.tag == DerValues.tagBoolean else { return false }
    guard reader.contentData(of: value) == Data([DerValues.booleanTrue]) else {
      throw ValidationFailure.malformed
    }
    value = try Self.requiredElement(
      from: &reader,
      in: encoded,
      tag: DerValues.tagOctetString
    )
    return true
  }

  /// Parses IssuingDistributionPoint and rejects the indirectCRL flag.
  private static func parseIssuingDistributionPoint(_ encoded: Data) throws {
    let sequence = try Self.onlyElement(in: encoded, tag: DerValues.tagSequence)
    var reader = DerReader(encoded, within: sequence)
    var previousTag: UInt8?
    while let field = try Self.nextElement(from: &reader, in: encoded) {
      guard previousTag.map({ previous in previous < field.tag }) ?? true else {
        throw ValidationFailure.malformed
      }
      previousTag = field.tag
      try Self.validateIssuingDistributionPointField(
        field,
        reader: reader
      )
    }
    guard reader.isAtEnd else { throw ValidationFailure.malformed }
  }

  /// Checks one IssuingDistributionPoint field's implicit DER value.
  private static func validateIssuingDistributionPointField(
    _ field: DerReader.Element,
    reader: DerReader
  ) throws {
    if field.tag == Self.tagContext4Primitive {
      guard reader.contentData(of: field) == Data([DerValues.booleanTrue]) else {
        throw ValidationFailure.malformed
      }
      throw ValidationFailure.indirectUnsupported
    }
    switch field.tag {
    case DerValues.tagContext0Constructed:
      guard !field.content.isEmpty else { throw ValidationFailure.malformed }

    case DerValues.tagContext1Primitive,
      DerValues.tagContext2Primitive,
      Self.tagContext5Primitive:
      guard reader.contentData(of: field) == Data([DerValues.booleanTrue]) else {
        throw ValidationFailure.malformed
      }

    case Self.tagContext3Primitive:
      let bits = reader.contentData(of: field)
      guard
        let unused = bits.first,
        unused <= Self.maximumUnusedBitCount,
        bits.count > 1
      else {
        throw ValidationFailure.malformed
      }

    default:
      throw ValidationFailure.malformed
    }
    throw ValidationFailure.scopeUnsupported
  }

  /// Reads one unsigned DER INTEGER and returns its minimal magnitude.
  private static func onlyUnsignedInteger(in encoded: Data) throws -> Data {
    _ = try Self.onlyElement(in: encoded, tag: DerValues.tagInteger)
    var reader = DerReader(encoded)
    guard let integer = reader.next() else {
      throw ValidationFailure.malformed
    }
    return try Self.unsignedIntegerContent(reader.contentData(of: integer))
  }

  /// Rejects critical semantics not otherwise implemented by this verifier.
  private static func rejectCritical(
    _ extensionValue: ExtensionValue
  ) throws {
    guard !extensionValue.isCritical else {
      throw ValidationFailure.unsupportedCriticalExtension
    }
  }
}
