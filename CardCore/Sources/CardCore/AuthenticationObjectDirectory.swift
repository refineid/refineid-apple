// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// EF.AOD: the length bounds of the card's password objects.
///
/// EF.AOD (Authentication Object Directory) lists the card's
/// authentication objects as ISO/IEC 7816-15 `AuthenticationObjectChoice`
/// values (FINEID S4-1 v4.2 §8.1.5; FINEID S4-2 v4.0 §4.6.10 and
/// §4.7.10). A password object carries `PasswordAttributes`:
///
/// ```text
/// PasswordAttributes ::= SEQUENCE {
///     pwdFlags      PasswordFlags,        -- BIT STRING
///     pwdType       PasswordType,         -- ENUMERATED
///     minLength     INTEGER,
///     storedLength  INTEGER,
///     maxLength     INTEGER OPTIONAL,
///     pwdReference  [0] Reference DEFAULT 0,
///     padChar       OCTET STRING OPTIONAL,
///     ... }
/// ```
///
/// A password object is deconstructed to the reference the card names
/// it by and the shortest and longest value it accepts. The longest is
/// `maxLength` when the card lists it, and `storedLength` otherwise.
internal struct AuthenticationObjectDirectory: Equatable, Sendable {
  /// One password object: the reference the card names it by and the
  /// length range it accepts.
  internal struct PasswordObject: Equatable, Sendable {
    /// `pwdReference` as the card lists it.
    internal let reference: UInt8

    /// `minLength` to `maxLength`, or to `storedLength` when
    /// `maxLength` is absent.
    internal let lengths: PasswordLengthRange
  }

  /// What one password object's content decodes to.
  private enum Decoded {
    case kept(PasswordObject)
    case malformed
    case notKept
  }

  /// The password objects, in file order.
  ///
  /// Objects of the other authentication kinds are not kept. A password
  /// object is kept only when its lengths count digits (`ascii-numeric`
  /// or `utf8`), its reference and lengths fit one octet, and its range
  /// satisfies `PasswordLengthRange`.
  internal let passwords: [PasswordObject]

  /// Parses the contents of EF.AOD; nil when the file does not decode.
  ///
  /// The file is a concatenation of authentication objects, optionally
  /// followed by zero padding to the file size. Every object must frame,
  /// and every password object must carry its mandatory
  /// `PasswordAttributes` elements under their tags; any failure there
  /// rejects the whole file.
  internal static func parse(_ data: Data) -> Self? {
    let bytes = Array(data)
    var found: [PasswordObject] = []
    var index = 0
    while index < bytes.count {
      if bytes[index] == Pkcs15Values.endOfContentsOctet {
        guard bytes[index...].allSatisfy({ $0 == Pkcs15Values.endOfContentsOctet }) else {
          return nil
        }
        break
      }
      guard let parsed = try? DerTlvRecord.record(in: bytes, at: index) else { return nil }
      index = parsed.end
      guard parsed.record.tag == Pkcs15Values.sequenceTag else { continue }
      switch passwordObject(in: parsed.record.value) {
      case .malformed:
        return nil

      case .notKept:
        continue

      case .kept(let password):
        found.append(password)
      }
    }
    return Self(passwords: found)
  }

  /// Decodes one password object's content: the common and class
  /// attributes, an optional subclass, and `typeAttributes [1]`.
  private static func passwordObject(in content: Data) -> Decoded {
    guard
      let children = try? DerTlvRecord.sequence(in: content),
      let typeAttributes = children.first(where: { $0.tag == Pkcs15Values.typeAttributesTag }),
      let wrapped = try? DerTlvRecord.sequence(in: typeAttributes.value),
      wrapped.count == 1,
      let attributes = wrapped.first,
      attributes.tag == Pkcs15Values.sequenceTag,
      let fields = try? DerTlvRecord.sequence(in: attributes.value)
    else {
      return .malformed
    }
    return passwordAttributes(fields)
  }

  /// Decodes `PasswordAttributes` by position: flags, type, minimum and
  /// stored length, then the optional maximum length and reference.
  private static func passwordAttributes(_ fields: [DerTlvRecord]) -> Decoded {
    var remaining = fields[...]
    guard
      let flags = remaining.popFirst(), flags.tag == DerValues.tagBitString,
      let type = remaining.popFirst(), type.tag == DerValues.tagEnumerated,
      let minimum = remaining.popFirst(), minimum.tag == DerValues.tagInteger,
      let stored = remaining.popFirst(), stored.tag == DerValues.tagInteger
    else {
      return .malformed
    }
    let maximum = remaining.first?.tag == DerValues.tagInteger ? remaining.popFirst() : nil
    let reference =
      remaining.first?.tag == Pkcs15Values.passwordReferenceTag ? remaining.popFirst() : nil
    let countsDigits = [Pkcs15Values.passwordTypeAsciiNumeric, Pkcs15Values.passwordTypeUtf8]
    guard let kind = unsignedOctet(type.value), countsDigits.contains(kind) else {
      return .notKept
    }
    let referenceValue =
      reference.map { unsignedOctet($0.value) } ?? Pkcs15Values.passwordReferenceDefault
    guard
      let referenceValue,
      let minimumValue = unsignedOctet(minimum.value),
      let maximumValue = unsignedOctet((maximum ?? stored).value),
      let lengths = PasswordLengthRange(
        minimum: Int(minimumValue), maximum: Int(maximumValue))
    else {
      return .notKept
    }
    return .kept(PasswordObject(reference: referenceValue, lengths: lengths))
  }

  /// An INTEGER or ENUMERATED content read as an unsigned magnitude that
  /// fits one octet.
  ///
  /// Leading zero octets are dropped, so both the DER form of a
  /// reference with its high bit set (a zero octet, then the reference)
  /// and the bare octet read as the reference. Nil for an empty content
  /// or a magnitude above one octet.
  private static func unsignedOctet(_ content: Data) -> UInt8? {
    guard let first = content.first else { return nil }
    let significant = content.drop { $0 == Pkcs15Values.endOfContentsOctet }
    guard !significant.isEmpty else { return first }
    return significant.count == 1 ? significant.first : nil
  }
}
