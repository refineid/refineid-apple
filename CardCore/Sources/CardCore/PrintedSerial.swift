// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The serial printed on the plastic card.
///
/// This is distinct from ``ChipSerial``. The chip serial is the security
/// binding for PIN memory and rejected credentials; the printed form is the
/// human-auditable part of the CryptoTokenKit ``TokenInstanceID``.
public struct PrintedSerial: Equatable, Hashable, Sendable {
  /// Both supported FINEID generations print nine serial characters.
  private static let length = 9

  /// The legacy PKCS#15 rendering is twenty decimal characters.
  private static let legacyFullLength = 20

  /// The printed nine-character window starts here in the legacy form.
  private static let legacyOffset = 10

  /// ASCII byte ranges used to reject invented Unicode serial forms.
  private static let asciiUppercase = UInt8(ascii: "A")...UInt8(ascii: "Z")
  private static let asciiLowercase = UInt8(ascii: "a")...UInt8(ascii: "z")
  private static let asciiDigits = UInt8(ascii: "0")...UInt8(ascii: "9")

  /// The exact serial as printed, preserving the card's letter case.
  public let value: String

  /// Applies the generation-specific conversion used by the Rust core.
  ///
  /// Current cards carry letters and print the last nine characters of
  /// their chip serial. Legacy cards carry a twenty-digit
  /// rendering and print characters 10 through 18. Unknown shapes are
  /// refused so a plausible-looking but false card name is never published.
  public init?(chipSerial: ChipSerial) {
    let full = chipSerial.value
    if full.utf8.contains(where: { byte in
      Self.asciiUppercase.contains(byte) || Self.asciiLowercase.contains(byte)
    }), full.utf8.count >= Self.length {
      let candidate = String(full.suffix(Self.length))
      guard candidate.utf8.allSatisfy(Self.isAsciiAlphanumeric) else {
        return nil
      }
      self.value = candidate
      return
    }
    if full.utf8.count == Self.legacyFullLength,
      full.utf8.allSatisfy({ byte in Self.asciiDigits.contains(byte) })
    {
      let start = full.index(full.startIndex, offsetBy: Self.legacyOffset)
      let end = full.index(start, offsetBy: Self.length)
      self.value = String(full[start..<end])
      return
    }
    return nil
  }

  /// Token identifiers accept only the card format's ASCII letters and digits.
  private static func isAsciiAlphanumeric(_ byte: UInt8) -> Bool {
    Self.asciiUppercase.contains(byte)
      || Self.asciiLowercase.contains(byte)
      || Self.asciiDigits.contains(byte)
  }
}
