// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The PKCS#15 tags a card's own directories are written in
/// (ISO 7816-15; FINEID S1 v4.2 uses the same encoding).
internal enum Pkcs15Values {
  /// Context tag of the privateKeys entry in EF.ODF, PKCS#15 [0].
  internal static let privateKeysTag: UInt8 = 0xA0

  /// Context tag of the certificates entry in EF.ODF, PKCS#15 [4].
  internal static let certificatesTag: UInt8 = 0xA4

  /// Context tag of an object's type attributes, PKCS#15 [1].
  internal static let typeAttributesTag: UInt8 = 0xA1

  /// Mask and value identifying any context-specific constructed tag,
  /// which is how an object entry of an unnamed class appears.
  internal static let contextTagMask: UInt8 = 0xF0
  internal static let contextTagValue: UInt8 = 0xA0

  /// Universal DER tags the directories use.
  internal static let sequenceTag: UInt8 = 0x30
  internal static let octetStringTag: UInt8 = 0x04
  internal static let integerTag: UInt8 = 0x02
  internal static let utf8StringTag: UInt8 = 0x0C

  /// `pwdReference [0]` of `PasswordAttributes`, an implicitly tagged
  /// INTEGER (ISO/IEC 7816-15).
  internal static let passwordReferenceTag: UInt8 = 0x80

  /// The `pwdReference` value when the card omits it (`DEFAULT 0`).
  internal static let passwordReferenceDefault: UInt8 = 0x00

  /// `pwdType` `ascii-numeric(1)`: one byte per digit, as FINEID cards
  /// list their PINs and the PUK.
  internal static let passwordTypeAsciiNumeric: UInt8 = 0x01

  /// `pwdType` `utf8(2)`: a digit is one byte, so the lengths count
  /// digits as for `ascii-numeric`.
  internal static let passwordTypeUtf8: UInt8 = 0x02

  /// The end-of-contents octet (ITU-T X.690 §8.1.5).
  ///
  /// No PKCS#15 object starts with it, so at an object boundary it
  /// begins the file's zero padding; as a leading INTEGER octet it is
  /// the sign octet.
  internal static let endOfContentsOctet: UInt8 = 0x00
}
