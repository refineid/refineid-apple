// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// A validated PIN1 value with single-use ownership.
///
/// PIN1 and PIN2 are distinct, non-interchangeable types; this type can
/// never satisfy a PIN2 parameter or enter any cache for PIN2. The type is
/// noncopyable: sending it to the card requires consuming it through
/// `consumeForSingleTransmission()`, so one user submission can cause at
/// most one credential-bearing command - the compiler, not review,
/// enforces at-most-once transport (Documentation/release-plan.md section 4.3).
///
/// The type is deliberately not `CustomStringConvertible`, not `Codable`,
/// and not copyable; its digits live in a zeroizing store.
public struct Pin1: ~Copyable {
  /// Shortest PIN1 the supported cards accept.
  public static let minimumDigitCount: Int = 4

  /// Longest PIN1 the supported cards accept.
  public static let maximumDigitCount: Int = 12

  private let store: ZeroizingDigitStore

  /// Validates and takes ownership of the entered digits.
  ///
  /// Refuses any input that is not 4-12 ASCII digits; there is no other
  /// way to construct a `Pin1`.
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

  /// Rebuilds a PIN1 that owns `store`, for accepted-PIN memory to re-issue.
  ///
  /// The cached bytes were a valid PIN1 when stored, so this
  /// reconstruction is total.
  internal init(owning store: ZeroizingDigitStore) {
    self.store = store
  }

  /// Non-reversible fingerprint of this PIN bound to one card and the
  /// PIN1 role, for the rejected-PIN memory.
  ///
  /// Reading the fingerprint does not consume the value: it is not a
  /// transmission.
  public borrowing func fingerprint(boundTo serial: ChipSerial) -> PinFingerprint {
    PinFingerprint.compute(digits: store, serial: serial, role: .pin1)
  }

  /// Consumes this PIN for exactly one card command.
  ///
  /// After this call the value no longer exists; a retry, replay, or
  /// resend needs a fresh user entry by construction.
  public consuming func consumeForSingleTransmission() -> Pin1Transmission {
    Pin1Transmission(store: store)
  }

  /// A fresh, independently-zeroized copy of these digits, for the cache.
  ///
  /// Borrowing: copying for the cache is not a transmission and does not
  /// consume the value.
  internal borrowing func cachedCopy() -> ZeroizingDigitStore {
    ZeroizingDigitStore(bytes: store.bytes)
  }
}
