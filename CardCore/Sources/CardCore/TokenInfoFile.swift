// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Extracts what EF.TokenInfo says about the card.
///
/// PKCS#15 TokenInfo is `SEQUENCE { version INTEGER, serialNumber OCTET
/// STRING, manufacturerID Label OPTIONAL, label [0] Label OPTIONAL,
/// ... }`. Current-card printable ASCII is decoded; legacy binary/BCD
/// remains hexadecimal, matching the reference implementation.
///
/// The two optional strings after it are what the card calls itself, and
/// they are worth reading for one reason: a status screen that can say
/// which card is in the reader is telling the holder something only the
/// card knows, instead of the same "identity card recognized" for every
/// card ever made. Both are optional and neither is trusted for
/// anything: they are shown, never matched on.
public enum TokenInfoFile {
  /// Current-card serials use this printable ASCII range.
  private static let printableAscii = UInt8(ascii: " ")...UInt8(ascii: "~")

  private static let hexDigits = Array("0123456789ABCDEF")

  private static let highNibbleShift = 4

  private static let hexDigitsPerByte = 2

  private static let minimumFieldCount = 2

  /// Parses the serial, or nil when the outer SEQUENCE, the leading
  /// INTEGER, or the serial octet string is missing or malformed.
  public static func serial(fromContent content: Data) -> ChipSerial? {
    guard
      let outer = try? DerTlvRecord.sequence(in: content),
      let sequence = outer.first,
      sequence.tag == Iso7816Values.derSequenceTag,
      let fields = try? DerTlvRecord.sequence(in: sequence.value),
      fields.count >= Self.minimumFieldCount,
      fields[0].tag == Iso7816Values.derIntegerTag,
      fields[1].tag == Iso7816Values.derOctetStringTag,
      !fields[1].value.isEmpty
    else {
      return nil
    }
    return ChipSerial(value: renderSerial(fields[1].value))
  }

  /// What the card calls itself: its manufacturer and its label, as far
  /// as it offers them, or nil when it offers neither.
  ///
  /// Display only. A card is identified by what it can do and what its
  /// certificate says, never by a string it hands out about itself.
  public static func description(fromContent content: Data) -> String? {
    guard
      let outer = try? DerTlvRecord.sequence(in: content),
      let sequence = outer.first,
      sequence.tag == Iso7816Values.derSequenceTag,
      let fields = try? DerTlvRecord.sequence(in: sequence.value)
    else {
      return nil
    }
    let named = fields.dropFirst(Self.minimumFieldCount).compactMap { field -> String? in
      guard
        field.tag == Iso7816Values.derUtf8StringTag
          || field.tag == Iso7816Values.derContextLabelTag
      else {
        return nil
      }
      // Failable rather than lossy: a label that is not valid UTF-8 is
      // not a label, and a string of replacement characters on a status
      // screen is worse than no name at all.
      guard let text = String(bytes: field.value, encoding: .utf8) else { return nil }
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    guard !named.isEmpty else { return nil }
    return named.joined(separator: " ")
  }

  private static func hexEncode(_ data: Data) -> String {
    var rendered = ""
    rendered.reserveCapacity(data.count * Self.hexDigitsPerByte)
    for byte in data {
      rendered.append(Self.hexDigits[Int(byte) >> Self.highNibbleShift])
      rendered.append(Self.hexDigits[Int(byte) & Int(Iso7816Values.lowNibbleMask)])
    }
    return rendered
  }

  /// Current cards store printable ASCII directly; legacy cards store
  /// binary/BCD bytes whose hexadecimal form is the stable serial.
  ///
  /// This mirrors `render_token_serial` in the Rust core. Keeping the raw
  /// hex for a current card can accidentally produce an all-decimal string,
  /// which then looks like neither supported generation and prevents the
  /// card from receiving a CryptoTokenKit identifier.
  private static func renderSerial(_ data: Data) -> String {
    if data.allSatisfy({ byte in Self.printableAscii.contains(byte) }),
      let printable = String(data: data, encoding: .utf8)
    {
      return printable
    }
    return hexEncode(data)
  }
}
