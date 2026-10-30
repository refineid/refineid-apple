// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// One PIN2 entry by the holder for one qualified signature or one batch of
/// them, kept in zeroizing memory for as long as its owner holds it, from
/// which single-use `Pin2` values are issued.
///
/// Each qualified signature of the operation gets its own noncopyable
/// `Pin2`, consumed by its VERIFY; the digits stay only in the entry's
/// store, zeroized when the last owner releases the entry. Nothing keeps
/// an entry beyond the operation it was entered for.
///
/// The type is deliberately not `CustomStringConvertible`, not `Codable`,
/// and not `Equatable`, and it reflects as an empty mirror.
public final class Pin2Entry: Sendable, CustomReflectable {
  private let store: ZeroizingDigitStore

  /// An empty mirror: reflection never reaches the digits.
  public var customMirror: Mirror {
    Mirror(self, children: [:])
  }

  /// Validates and takes the digits the platform's text field delivered.
  ///
  /// Refuses anything a `Pin2` refuses; the caller drops its `String`
  /// at once.
  public init?(digits: String) {
    guard
      let digitStore = CredentialDigits.validated(
        digits,
        minimumCount: Pin2.minimumDigitCount,
        maximumCount: Pin2.maximumDigitCount
      )
    else {
      return nil
    }
    self.store = digitStore
  }

  /// A fresh `Pin2` for one card command, over its own zeroizing copy of
  /// the digits.
  public func issue() -> Pin2 {
    Pin2(owning: ZeroizingDigitStore(bytes: store.bytes))
  }

  /// Non-reversible fingerprint of these digits in the PIN2 role, bound to
  /// no card, for a rejected-PIN memory that lives exactly as long as one
  /// card session.
  public func sessionFingerprint() -> PinFingerprint {
    PinFingerprint.compute(digits: store, serial: nil, role: .pin2)
  }
}
