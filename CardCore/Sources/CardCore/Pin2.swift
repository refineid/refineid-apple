// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// A validated PIN2 value with single-use ownership.
///
/// PIN2 authorises the qualified-signature key and nothing else. PIN1
/// and PIN2 are distinct, non-interchangeable types; this type can never
/// satisfy a PIN1 parameter. Unlike PIN1 it has no cache path at all:
/// there is no accepted-PIN2 memory and no reconstruction after
/// consumption, so every qualified signature costs a fresh entry
/// (Documentation/typing-discipline.md).
///
/// The type is deliberately not `CustomStringConvertible`, not `Codable`,
/// and not copyable; its digits live in a zeroizing store.
public struct Pin2: ~Copyable {
  /// Shortest PIN2 the supported cards accept (FINEID S4-1).
  public static let minimumDigitCount: Int = 6

  /// Longest PIN2 the supported cards accept.
  public static let maximumDigitCount: Int = 12

  private let store: ZeroizingDigitStore

  /// Validates and takes ownership of the entered digits.
  ///
  /// Refuses any input that is not 6-12 ASCII digits; there is no other
  /// way to construct a `Pin2`.
  public init?(digits: String) {
    guard
      let digitStore = CredentialDigits.validated(
        digits,
        minimumCount: Self.minimumDigitCount,
        maximumCount: Self.maximumDigitCount
      )
    else {
      return nil
    }
    self.store = digitStore
  }

  /// Non-reversible fingerprint of this PIN bound to one card and the
  /// PIN2 role, for the rejected-PIN memory.
  ///
  /// Reading the fingerprint does not consume the value: it is not a
  /// transmission.
  public borrowing func fingerprint(boundTo serial: ChipSerial) -> PinFingerprint {
    PinFingerprint.compute(digits: store, serial: serial, role: .pin2)
  }

  /// Consumes this PIN for exactly one card command.
  ///
  /// After this call the value no longer exists; a retry, replay, or
  /// resend needs a fresh user entry by construction.
  public consuming func consumeForSingleTransmission() -> Pin2Transmission {
    Pin2Transmission(store: store)
  }
}
