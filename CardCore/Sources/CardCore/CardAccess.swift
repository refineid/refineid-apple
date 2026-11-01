// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// EF.CardAccess: the PACE suites a card publishes before any channel
/// exists (BSI TR-03110-3 sections A.1 and A.1.2.1, table 2).
///
/// The file is unprotected, and domain parameters a terminal has not
/// verified can leak the password (section A.2.1.3), so only the
/// standardized domain parameters of ``PaceDomain`` are admitted. Other
/// entries -- other protocols, chip-authentication mapping, other ciphers,
/// other versions, explicit domain parameters -- are not kept; a malformed
/// entry of a suite this build runs fails the parse.
///
/// The citizen cards publish generic and chip-authentication mapping over
/// brainpoolP384r1 (FINEID S4-1 v4.2 section 3.2); the organization cards
/// publish generic and integrated mapping over NIST P-256 and P-384
/// (FINEID S4-2 v4.0 section 6).
public struct CardAccess: Equatable, Sendable {
  /// Why EF.CardAccess did not parse.
  public enum Failure: Error, Equatable, Sendable {
    /// A `PACEInfo` of a suite this build runs does not have the version
    /// and optional parameter identifier, as minimal DER INTEGERs, and
    /// nothing else (BSI TR-03110-3 appendix A.1.1.1).
    case malformedPaceInfo

    /// An element of the set is not a `SEQUENCE` that starts with its
    /// protocol object identifier.
    case malformedSecurityInfo

    /// The file is not one DER `SET OF SecurityInfo` and nothing else.
    case notSecurityInfos
  }

  /// Version and parameter identifier: the fields after the protocol.
  private static let paceInfoFieldLimit = 2

  /// A sign-padded octet: the pad and the value.
  private static let paddedOctetCount = 2

  /// The parsed suites, in the order the card lists them.
  public let suites: [PaceInfo]

  /// The generic-mapping suite the handshake runs.
  ///
  /// The listed one over the most preferred domain parameter; nil when the
  /// card lists none.
  public var genericMappingSuite: PaceInfo? {
    for domain in PaceDomain.preference {
      if let suite = suites.first(where: { $0.mapping == .generic && $0.domain == domain }) {
        return suite
      }
    }
    return nil
  }

  /// Parses EF.CardAccess as read from the card.
  public static func parse(_ der: Data) throws(Failure) -> Self {
    guard
      let records = try? DerTlvRecord.sequence(in: der),
      records.count == 1,
      let set = records.first,
      set.tag == CardAccessValues.setTag,
      let entries = try? DerTlvRecord.sequence(in: set.value)
    else {
      throw .notSecurityInfos
    }
    var parsed: [PaceInfo] = []
    for entry in entries {
      guard
        entry.tag == CardAccessValues.sequenceTag,
        let fields = try? DerTlvRecord.sequence(in: entry.value),
        let protocolField = fields.first,
        protocolField.tag == CardAccessValues.objectIdentifierTag
      else {
        throw .malformedSecurityInfo
      }
      if let suite = try Self.suite(
        protocolOid: Array(protocolField.value),
        fields: Array(fields.dropFirst())
      ) {
        parsed.append(suite)
      }
    }
    return Self(suites: parsed)
  }

  /// The suite one `SecurityInfo` names, nil when it is well formed and not
  /// one this build runs.
  ///
  /// ```text
  /// PACEInfo ::= SEQUENCE {
  ///   protocol    OBJECT IDENTIFIER,
  ///   version     INTEGER,
  ///   parameterId INTEGER OPTIONAL
  /// }
  /// ```
  private static func suite(
    protocolOid: [UInt8],
    fields: [DerTlvRecord]
  ) throws(Failure) -> PaceInfo? {
    let mapping: PaceMapping
    switch protocolOid {
    case PaceValues.protocolOidBody:
      mapping = .generic

    case PaceValues.integratedMappingOidBody:
      mapping = .integrated

    default:
      return nil
    }
    guard let versionField = fields.first, fields.count <= Self.paceInfoFieldLimit else {
      throw .malformedPaceInfo
    }
    let version = try Self.smallUnsigned(versionField)
    let parameterID = try fields.dropFirst().first.map(Self.smallUnsigned)
    guard
      version == PaceValues.paceInfoVersion,
      let identifier = parameterID.flatMap(\.self),
      let domain = PaceDomain(parameterID: identifier)
    else {
      return nil
    }
    return PaceInfo(mapping: mapping, domain: domain)
  }

  /// A `PACEInfo` INTEGER field: the value from zero to the largest octet,
  /// nil for a negative or larger value, which names nothing this build
  /// runs (ITU-T X.690 sections 8.3.1 and 8.3.2).
  private static func smallUnsigned(_ field: DerTlvRecord) throws(Failure) -> UInt8? {
    guard field.tag == CardAccessValues.integerTag else { throw .malformedPaceInfo }
    let octets = Array(field.value)
    guard let first = octets.first else { throw .malformedPaceInfo }
    if octets.count == 1 {
      return first & CardAccessValues.integerSignBit == 0 ? first : nil
    }
    let second = octets[1]
    let redundantPad =
      first == CardAccessValues.integerPadOctet
      && second & CardAccessValues.integerSignBit == 0
    let redundantSign =
      first == CardAccessValues.integerSignExtensionOctet
      && second & CardAccessValues.integerSignBit != 0
    guard !redundantPad, !redundantSign else { throw .malformedPaceInfo }
    if octets.count == Self.paddedOctetCount, first == CardAccessValues.integerPadOctet {
      return second
    }
    return nil
  }

}
