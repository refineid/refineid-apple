// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import CardCore

/// EF.AOD contents assembled from the same named constants the parser
/// reads, one password object at a time (ISO/IEC 7816-15
/// `PasswordAttributes`; FINEID S4-1 v4.2 §8.1.5).
internal struct AuthenticationObjectFixture {
  /// The stored length FINEID password objects list.
  internal static let storedLength: UInt8 = 12

  /// `pwdType` `bcd(0)`: lengths that do not count one digit per byte.
  internal static let passwordTypeBcd: UInt8 = 0

  /// The tag and short-form length octets a small TLV starts with.
  private static let shortFormHeaderCount = 2

  /// The label of the fixture objects; not consulted.
  private static let label = "perustunnusluku"

  /// The authId of the fixture objects; not consulted.
  private static let authenticationIdentifier: UInt8 = 1

  /// `pwdFlags` octet of the fixture objects; not consulted.
  private static let flagsOctet: UInt8 = 0

  /// `padChar` of the fixture objects.
  private static let padCharacter: UInt8 = 0

  internal var passwordType = Pkcs15Values.passwordTypeAsciiNumeric
  internal var minimum: Int
  internal var stored = Int(Self.storedLength)
  internal var maximum: Int?
  internal var reference: UInt8?

  /// The `PasswordAttributes` SEQUENCE content.
  internal var attributes: Data {
    var fields = [
      DerEncoder.tlv(
        DerValues.tagBitString, Data([DerValues.bitStringNoUnusedBits, Self.flagsOctet])),
      DerEncoder.tlv(DerValues.tagEnumerated, Data([passwordType])),
      DerEncoder.integer(minimum),
      DerEncoder.integer(stored),
    ]
    if let maximum {
      fields.append(DerEncoder.integer(maximum))
    }
    if let reference {
      fields.append(
        DerEncoder.tlv(Pkcs15Values.passwordReferenceTag, Self.integerContent(Int(reference))))
    }
    fields.append(DerEncoder.octetString(Data([Self.padCharacter])))
    return fields.reduce(Data(), +)
  }

  /// The whole authentication object around `attributes`.
  internal var encoded: Data {
    Self.object(aroundAttributes: attributes)
  }

  /// A citizen-card object: ascii-numeric, stored length twelve, no
  /// maximum.
  internal static func citizen(reference: UInt8, minimum: Int) -> Self {
    Self(minimum: minimum, reference: reference)
  }

  /// A file of `objects`, followed by `padding` zero octets.
  internal static func file(_ objects: [Data], padding: Int) -> Data {
    objects.reduce(Data(), +)
      + Data(repeating: Pkcs15Values.endOfContentsOctet, count: padding)
  }

  /// A file of `objects` with no padding.
  internal static func file(_ objects: [Data]) -> Data {
    file(objects, padding: 0)
  }

  /// The INTEGER content of `value`, minimal DER: a zero octet first
  /// when the high bit is set.
  internal static func integerContent(_ value: Int) -> Data {
    Data(DerEncoder.integer(value).dropFirst(shortFormHeaderCount))
  }

  /// An authentication object wrapping `attributes` content: common and
  /// class attributes, then `typeAttributes [1]`.
  internal static func object(aroundAttributes attributes: Data) -> Data {
    DerEncoder.sequence([
      DerEncoder.sequence([DerEncoder.tlv(DerValues.tagUtf8String, Data(label.utf8))]),
      DerEncoder.sequence([DerEncoder.octetString(Data([authenticationIdentifier]))]),
      DerEncoder.tlv(Pkcs15Values.typeAttributesTag, DerEncoder.sequence([attributes])),
    ])
  }
}
