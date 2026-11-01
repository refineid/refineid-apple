// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore

/// The digits one credential field takes on the card in session: the
/// card's accepted range for the credential the field holds.
internal struct PinEntryLimits: Equatable {
  /// The lengths the card accepts; nil when it accepts none, and no
  /// entry is complete.
  private let accepted: PasswordLengthRange?

  /// The longest entry the field keeps when the card accepts no length.
  private let capacity: Int

  internal init(_ lengths: CardPinLengths, role: CredentialRole) {
    accepted = lengths.lengths(for: role).accepted
    capacity = role == .puk ? Puk.maximumDigitCount : Pin1.maximumDigitCount
  }

  /// Whether `entry` has a length the card accepts.
  internal func accepts(_ entry: String) -> Bool {
    accepted?.contains(entry.count) ?? false
  }

  /// The typed text kept to ASCII digits, up to the card's longest
  /// value.
  internal func limited(_ text: String) -> String {
    LimitedDigits.digits(text, maximumCount: accepted?.maximum ?? capacity)
  }
}
