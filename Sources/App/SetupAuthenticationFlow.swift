// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// When the setup authentication prompt starts its NFC hold by itself.
///
/// A personal card's entry is exactly its six printed digits, so the
/// sixth digit completes it and the hold starts without another tap; a
/// photo scan lands on the same length and starts the same way. An
/// organization card's PIN 1 runs four to twelve digits, so only the
/// twelfth digit can complete it; anything shorter waits for the
/// explicit start button.
internal enum SetupAuthenticationFlow: Sendable {
  /// Whether `entry` is complete enough to start the hold by itself.
  ///
  /// A UI heuristic only: the hold still proves the entry against the
  /// card, and the card on the antenna has the last word on what the
  /// digits were.
  internal static func shouldBeginHold(entry: String, organizationMode: Bool) -> Bool {
    if organizationMode {
      return Self.isLongestPin1(entry)
    }
    return CardAccessNumber(digits: entry) != nil
  }

  /// Whether `entry` is twelve ASCII digits: the longest PIN 1, and so
  /// the only organization entry no further digit can extend.
  private static func isLongestPin1(_ entry: String) -> Bool {
    let asciiDigits = UInt8(ascii: "0")...UInt8(ascii: "9")
    return entry.utf8.count == Pin1.maximumDigitCount
      && entry.utf8.allSatisfy({ asciiDigits.contains($0) })
  }
}
