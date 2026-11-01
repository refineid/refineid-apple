// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// Keeps a credential field inside its domain: ASCII digits, bounded.
///
/// Keyboard types are hints, not validation. Paste, hardware keyboards
/// and accessibility input can all insert something else, and a numeric
/// keypad cannot stop a seventh digit from reaching a six-digit field.
///
/// These are functions rather than a `Binding` wrapper, and that is the
/// whole point. A binding whose setter clamps leaves its own
/// `wrappedValue` unchanged when the clamp bites -- the field held six
/// digits before the seventh and holds six after it -- so SwiftUI sees
/// no change, does not re-render, and the field goes on displaying the
/// seventh digit it was never given. Clamping through `onChange` writes
/// the shorter value back to the state that the field is bound to, which
/// is a change, which redraws.
internal enum LimitedDigits {
  /// A card access number: six ASCII digits and no more.
  internal static func cardAccessNumber(_ text: String) -> String {
    Self.digits(text, maximumCount: CardAccessNumber.digitCount)
  }

  /// Any PIN entry: ASCII digits up to the shared PIN maximum, which
  /// PIN1 and PIN2 both have.
  internal static func pin(_ text: String) -> String {
    Self.digits(text, maximumCount: Pin1.maximumDigitCount)
  }

  /// A PUK: ASCII digits up to the PUK maximum.
  internal static func puk(_ text: String) -> String {
    Self.digits(text, maximumCount: Puk.maximumDigitCount)
  }

  /// An activation entry: ASCII digits up to the scheme's exact count,
  /// or the activation code's, the longer one, while the scheme is not
  /// yet known.
  internal static func activationEntry(_ text: String, scheme: ActivationScheme?) -> String {
    Self.digits(
      text,
      maximumCount: scheme?.activationEntryDigitCount
        ?? ActivationScheme.activationCodeDigitCount)
  }

  /// Keeps only ASCII digits, in order, up to `maximumCount`.
  internal static func digits(_ text: String, maximumCount: Int) -> String {
    let asciiDigits = UInt8(ascii: "0")...UInt8(ascii: "9")
    let bytes = text.utf8.lazy
      .filter { byte in asciiDigits.contains(byte) }
      .prefix(maximumCount)
    return String(bytes: bytes, encoding: .ascii) ?? ""
  }
}
