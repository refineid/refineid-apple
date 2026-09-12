// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What a card advertises it can do before any secure channel exists.
///
/// EF.CardAccess sits in the main file and is readable with no
/// authentication -- that is its purpose: a terminal cannot run PACE
/// until the card has told it which variants and domain parameters it
/// supports (ICAO 9303-11 section 9.2.11).
///
/// RefineID runs a fixed suite rather than negotiating one, so nothing
/// in the login path reads this file. It is read to answer a question
/// the fixed suite cannot: whether the card would accept a cheaper one.
/// Generic mapping costs the card a Diffie-Hellman that integrated
/// mapping does not, and a smaller curve costs it less again -- both
/// were measured dominating an NFC login.
///
/// Nothing here is trusted: an entry is reported only when its bytes
/// parse, and an unrecognized protocol is reported by its dotted
/// identifier rather than guessed at.
public enum CardAccessFile {
  /// One advertised protocol, named as far as the bytes allow.
  public struct SecurityInfo: Equatable, Sendable {
    /// The dotted object identifier, always present.
    public let objectIdentifier: String

    /// The specification's name for it, when this build knows one.
    public let protocolName: String?

    /// The protocol version the card states.
    public let version: Int?

    /// The standardized domain parameter selector, when carried.
    public let parameterID: Int?

    /// What that selector names, when this build knows it.
    public let parameterName: String?

    /// Whether this entry is a member of the PACE family.
    public let isPace: Bool

    /// Whether this entry spares the card the mapping Diffie-Hellman.
    ///
    /// The one property a caller comparing suites is looking for, so it
    /// is decided here from the parsed arc rather than by matching the
    /// name back into pieces.
    public let usesIntegratedMapping: Bool

    /// One line for a report, naming everything that parsed.
    public var summary: String {
      var text = protocolName ?? objectIdentifier
      if let version {
        text += " v\(version)"
      }
      if let parameterID {
        text += " param=\(parameterID)"
        if let parameterName {
          text += " (\(parameterName))"
        }
      }
      if protocolName != nil {
        text += " [\(objectIdentifier)]"
      }
      return text
    }
  }

  /// Parses the file's DER into every SecurityInfo it carries.
  ///
  /// Empty means nothing could be read from these bytes, whether
  /// because they are not the DER SET the file must be or because no
  /// entry inside it parsed. The two are one answer to every caller:
  /// this card told us nothing we can act on. An individual entry that
  /// does not parse is skipped rather than failing the whole read, so a
  /// protocol this build has no parser for costs only itself.
  public static func parse(_ der: Data) -> [SecurityInfo] {
    guard
      let records = try? DerTlvRecord.sequence(in: der),
      let set = records.first(where: { $0.tag == CardAccessValues.setTag }),
      let entries = try? DerTlvRecord.sequence(in: set.value)
    else {
      return []
    }
    return
      entries
      .filter { $0.tag == CardAccessValues.sequenceTag }
      .compactMap(Self.securityInfo(in:))
  }

  /// Reads one SecurityInfo SEQUENCE.
  private static func securityInfo(in record: DerTlvRecord) -> SecurityInfo? {
    guard
      let fields = try? DerTlvRecord.sequence(in: record.value),
      let identifier = fields.first(where: { $0.tag == CardAccessValues.objectIdentifierTag })
    else {
      return nil
    }
    let integers =
      fields
      .filter { $0.tag == CardAccessValues.integerTag }
      .compactMap(Self.integer(in:))
    let pace = Self.pace(identifier.value)
    // Order is what tells the two integers apart: PACEInfo carries
    // version first and the optional parameter id second
    // (BSI TR-03110-3 appendix A.1.1.1).
    let parameterID = integers.count > 1 ? integers[1] : nil
    return SecurityInfo(
      objectIdentifier: Self.dotted(identifier.value),
      protocolName: pace?.name,
      version: integers.first,
      parameterID: parameterID,
      parameterName: parameterID.flatMap(CardAccessValues.domainParameterName),
      isPace: pace != nil,
      usesIntegratedMapping: pace?.mapping.isIntegrated ?? false)
  }

  /// The value of a DER INTEGER small enough to be one of these fields.
  ///
  /// Versions and parameter ids are single-byte in every registered
  /// case; anything longer is not one of them and is left unread rather
  /// than truncated into a plausible-looking number.
  private static func integer(in record: DerTlvRecord) -> Int? {
    guard record.value.count == 1, let byte = record.value.first else { return nil }
    return Int(byte)
  }

  /// The mapping and full name of a PACE identifier, or nil when these
  /// bytes are not one.
  private static func pace(_ bytes: Data) -> (mapping: CardAccessValues.Mapping, name: String)? {
    let prefix = CardAccessValues.bsiSmartcardPrefix
    // Family, mapping and cipher are the three arcs after the prefix.
    let arcs = bytes.dropFirst(prefix.count)
    guard
      bytes.count == prefix.count + CardAccessValues.paceArcCount,
      Array(bytes.prefix(prefix.count)) == prefix,
      arcs[arcs.startIndex + CardAccessValues.paceFamilyOffset] == CardAccessValues.familyPace,
      let mapping = CardAccessValues.Mapping(
        rawValue: arcs[arcs.startIndex + CardAccessValues.paceMappingOffset]),
      let cipher = CardAccessValues.Cipher(
        rawValue: arcs[arcs.startIndex + CardAccessValues.paceCipherOffset])
    else {
      return nil
    }
    return (mapping, "PACE-" + mapping.name + "-" + cipher.name)
  }

  /// The dotted form of a DER object identifier's content bytes.
  ///
  /// The first byte carries two arcs; every later arc is base-128 with
  /// the top bit marking continuation (ITU-T X.690 section 8.19).
  private static func dotted(_ bytes: Data) -> String {
    guard let first = bytes.first else { return "" }
    var arcs = [
      String(Int(first) / CardAccessValues.objectIdentifierFirstArcScale),
      String(Int(first) % CardAccessValues.objectIdentifierFirstArcScale),
    ]
    var value = 0
    for byte in bytes.dropFirst() {
      value =
        value << CardAccessValues.objectIdentifierShift
        | Int(byte & CardAccessValues.objectIdentifierValueMask)
      if byte & CardAccessValues.objectIdentifierContinuation == 0 {
        arcs.append(String(value))
        value = 0
      }
    }
    return arcs.joined(separator: ".")
  }
}
