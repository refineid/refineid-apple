// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What a card says about its own objects, read from its PKCS#15
/// directories instead of from known file identifiers.
///
/// EF.ODF names where the certificate and private-key directories
/// live; each of those lists its objects with a common identifier, and
/// a certificate belongs to the key that carries the same one. The key
/// entry also carries the reference the card selects that key by, which
/// is the value MSE:SET needs and which nothing outside the card
/// defines (FINEID S1 v4.2: the reference is derived from
/// PrivateKeyAttributes.keyReference).
public enum Pkcs15Directory {
  /// One certificate the card lists.
  public struct Certificate: Equatable, Sendable {
    /// The label the card publishes for it.
    public let label: String

    /// The identifier shared with the key it belongs to.
    public let identifier: Data

    /// The elementary file holding the certificate (trailing component of ``path``).
    public let file: FileIdentifier

    /// The full file path inside the application, with any leading MF (`3F00`) stripped.
    public let path: [FileIdentifier]

    /// Builds a certificate entry with a full path; ``file`` is the trailing EF.
    public init(label: String, identifier: Data, path: [FileIdentifier]) {
      guard let trailing = path.last else {
        preconditionFailure("certificate path must contain at least one file identifier")
      }
      self.label = label
      self.identifier = identifier
      self.file = trailing
      self.path = path
    }
  }

  /// Intended cryptographic usage flags parsed from `CommonKeyAttributes.usage`.
  public struct KeyUsage: OptionSet, Equatable, Sendable {
    /// Key may produce authentication / general signatures (`sign`, bit 2).
    public static let sign = Self(rawValue: 1 << 0)

    /// Key produces legally binding qualified signatures (`nonRepudiation`, bit 9).
    public static let nonRepudiation = Self(rawValue: 1 << 1)

    /// Underlying bit mask.
    public let rawValue: UInt8

    /// Creates a usage option set from a bit mask.
    public init(rawValue: UInt8) {
      self.rawValue = rawValue
    }
  }

  /// One private key the card lists.
  public struct PrivateKey: Equatable, Sendable {
    /// The label the card publishes for it.
    public let label: String

    /// The identifier shared with the certificate it signs for.
    public let identifier: Data

    /// The reference the card selects this key by, absent when the
    /// card leaves the optional field out.
    public let keyReference: UInt8?

    /// Usage flags declared in `CommonKeyAttributes.usage`.
    public let usage: KeyUsage

    /// Builds a private-key directory entry.
    public init(
      label: String,
      identifier: Data,
      keyReference: UInt8?,
      usage: KeyUsage
    ) {
      self.label = label
      self.identifier = identifier
      self.keyReference = keyReference
      self.usage = usage
    }
  }

  /// Where EF.ODF says the directories are.
  public struct Locations: Equatable, Sendable {
    /// The authentication-object directory file (`EF.AOD`).
    public let authObjects: FileIdentifier?

    /// The certificate directory file (`EF.CD`).
    public let certificates: FileIdentifier?

    /// The private-key directory file (`EF.PrKD`).
    public let privateKeys: FileIdentifier?
  }

  /// Maximum number of file-identifier segments accepted in one PKCS#15 path.
  internal static let maximumPathDepth = 8

  /// Bytes in a file identifier.
  private static let fileIdentifierOctets = 2

  /// Bit positions the high octet of a file identifier occupies.
  private static let highOctetShift: UInt16 = 8

  /// Minimum octets in a BIT STRING payload carrying byte 0 (unused-bits byte + octet 0).
  private static let minimumUsageOctetsForSign = 2

  /// Minimum octets in a BIT STRING payload carrying byte 1 (unused-bits byte + octets 0..1).
  private static let minimumUsageOctetsForNonRepudiation = 3

  /// Byte index of usage octet 0 (`sign`) inside a BIT STRING payload (after unused-bits byte).
  private static let signUsageByteIndex = 1

  /// Byte index of usage octet 1 (`nonRepudiation`) inside a BIT STRING payload.
  private static let nonRepudiationUsageByteIndex = 2

  /// Reads EF.ODF and answers where the directories live.
  ///
  /// A path names a file by its trailing identifier; the leading
  /// components repeat the application the reader has already
  /// selected.
  public static func locations(fromObjectDirectory data: Data) -> Locations {
    var authObjects: FileIdentifier?
    var certificates: FileIdentifier?
    var privateKeys: FileIdentifier?
    for entry in (try? DerTlvRecord.sequence(in: data)) ?? [] {
      let isDirectoryEntry =
        entry.tag == Pkcs15Values.certificatesTag
        || entry.tag == Pkcs15Values.privateKeysTag
        || entry.tag == Pkcs15Values.authObjectsTag
      guard isDirectoryEntry,
        let path = try? DerTlvRecord.sequence(in: entry.value).first,
        path.tag == Pkcs15Values.sequenceTag,
        let octets = try? DerTlvRecord.sequence(in: path.value).first,
        octets.tag == Pkcs15Values.octetStringTag,
        let file = fileIdentifiers(fromPath: octets.value).last
      else { continue }
      if entry.tag == Pkcs15Values.certificatesTag {
        certificates = file
      } else if entry.tag == Pkcs15Values.privateKeysTag {
        privateKeys = file
      } else if entry.tag == Pkcs15Values.authObjectsTag {
        authObjects = file
      }
    }
    return Locations(
      authObjects: authObjects,
      certificates: certificates,
      privateKeys: privateKeys)
  }

  /// Reads the certificate directory.
  public static func certificates(fromDirectory data: Data) -> [Certificate] {
    entries(in: data).compactMap { entry in
      guard let common = commonAttributes(in: entry) else { return nil }
      let path = certificatePath(in: entry)
      guard !path.isEmpty else { return nil }
      return Certificate(
        label: common.label, identifier: common.identifier, path: path)
    }
  }

  /// Reads the private-key directory.
  public static func privateKeys(fromDirectory data: Data) -> [PrivateKey] {
    entries(in: data).compactMap { entry in
      guard let common = commonAttributes(in: entry) else { return nil }
      return PrivateKey(
        label: common.label,
        identifier: common.identifier,
        keyReference: keyReference(in: entry),
        usage: keyUsage(in: entry))
    }
  }

  /// The records of one directory file, ignoring padding the card
  /// leaves after the last one.
  private static func entries(in data: Data) -> [DerTlvRecord] {
    ((try? DerTlvRecord.sequence(in: data)) ?? []).filter { record in
      let isContextTag =
        record.tag & Pkcs15Values.contextTagMask == Pkcs15Values.contextTagValue
      return record.tag == Pkcs15Values.sequenceTag || isContextTag
    }
  }

  /// The label and identifier every object entry carries: the label
  /// from its common object attributes, the identifier from the class
  /// attributes that follow.
  private static func commonAttributes(
    in entry: DerTlvRecord
  ) -> (label: String, identifier: Data)? {
    let fields = (try? DerTlvRecord.sequence(in: entry.value)) ?? []
    guard let objectAttributes = fields.first, objectAttributes.tag == Pkcs15Values.sequenceTag,
      let labelRecord = (try? DerTlvRecord.sequence(in: objectAttributes.value))?.first,
      labelRecord.tag == Pkcs15Values.utf8StringTag,
      let label = String(data: labelRecord.value, encoding: .utf8),
      fields.count > 1,
      let identifier = (try? DerTlvRecord.sequence(in: fields[1].value))?.first,
      identifier.tag == Pkcs15Values.octetStringTag
    else { return nil }
    return (label, identifier.value)
  }

  /// The file path a certificate entry points at, with any leading `3F00` stripped.
  ///
  /// The type attributes hold the certificate's own attributes, which
  /// hold the path, which holds the octets: three descents, because a
  /// PKCS#15 path is a structure and not a bare string.
  private static func certificatePath(in entry: DerTlvRecord) -> [FileIdentifier] {
    let fields = (try? DerTlvRecord.sequence(in: entry.value)) ?? []
    guard let typeAttributes = fields.first(where: { $0.tag == Pkcs15Values.typeAttributesTag }),
      let attributes = (try? DerTlvRecord.sequence(in: typeAttributes.value))?.first,
      let path = (try? DerTlvRecord.sequence(in: attributes.value))?.first,
      let octets = (try? DerTlvRecord.sequence(in: path.value))?.first,
      octets.tag == Pkcs15Values.octetStringTag
    else { return [] }
    return fileIdentifiers(fromPath: octets.value)
  }

  /// The key reference a private-key entry carries, when it has one.
  ///
  /// It is the last INTEGER of the class attributes, which precede the
  /// type attributes; the fields before it are the identifier, the
  /// usage flags and the native marker.
  private static func keyReference(in entry: DerTlvRecord) -> UInt8? {
    let fields = (try? DerTlvRecord.sequence(in: entry.value)) ?? []
    guard fields.count > 1,
      let attributes = try? DerTlvRecord.sequence(in: fields[1].value),
      let reference = attributes.last(where: { $0.tag == Pkcs15Values.integerTag }),
      reference.value.count == 1
    else { return nil }
    return reference.value.first
  }

  /// The `CommonKeyAttributes.usage` BIT STRING parsed into ``KeyUsage``.
  private static func keyUsage(in entry: DerTlvRecord) -> KeyUsage {
    let fields = (try? DerTlvRecord.sequence(in: entry.value)) ?? []
    guard fields.count > 1,
      let attributes = try? DerTlvRecord.sequence(in: fields[1].value),
      let bitString = attributes.first(where: { $0.tag == DerValues.tagBitString })
    else {
      return []
    }
    let bytes = Array(bitString.value)
    var usage: KeyUsage = []
    if bytes.count >= Self.minimumUsageOctetsForSign,
      bytes[Self.signUsageByteIndex] & Pkcs15Values.keyUsageSignBitMask != 0
    {
      usage.insert(.sign)
    }
    if bytes.count >= Self.minimumUsageOctetsForNonRepudiation,
      bytes[Self.nonRepudiationUsageByteIndex] & Pkcs15Values.keyUsageNonRepudiationBitMask != 0
    {
      usage.insert(.nonRepudiation)
    }
    return usage
  }

  /// Splits a PKCS#15 path octet string into two-byte file identifiers,
  /// stripping a leading MF (`3F00`) when inner segments follow.
  private static func fileIdentifiers(fromPath path: Data) -> [FileIdentifier] {
    let bytes = Array(path)
    guard
      !bytes.isEmpty,
      bytes.count.isMultiple(of: Self.fileIdentifierOctets),
      bytes.count <= Self.maximumPathDepth * Self.fileIdentifierOctets
    else {
      return []
    }
    var result: [FileIdentifier] = []
    var index = 0
    while index < bytes.count {
      let high = UInt16(bytes[index]) << Self.highOctetShift
      let low = UInt16(bytes[index + 1])
      result.append(FileIdentifier(value: high | low))
      index += Self.fileIdentifierOctets
    }
    if result.count > 1, result.first == .mainFile {
      result.removeFirst()
    }
    return result
  }
}
