// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// One PIN1 entry by the holder, kept in zeroizing memory for as long as
/// its owner holds it, from which single-use `Pin1` values are issued.
///
/// The entry is the custody form of PIN1 for a path that hands one entry
/// through prompts, queues and actors and spends it on more than one card
/// command: each command gets its own noncopyable `Pin1`, consumed by that
/// command, and the digits stay only in the entry's store. The store is
/// zeroized when the last owner releases the entry.
///
/// The type is deliberately not `CustomStringConvertible`, not `Codable`,
/// and not `Equatable`, and it reflects as an empty mirror.
public final class Pin1Entry: Sendable, CustomReflectable {
  private let store: ZeroizingDigitStore

  /// An empty mirror: reflection never reaches the digits.
  public var customMirror: Mirror {
    Mirror(self, children: [:])
  }

  /// Validates and takes the digits the platform's text field delivered.
  ///
  /// Refuses anything a `Pin1` refuses; the caller drops its `String`
  /// at once.
  public init?(digits: String) {
    guard
      let digitStore = CredentialDigits.validated(
        digits,
        minimumCount: Pin1.minimumDigitCount,
        maximumCount: Pin1.maximumDigitCount
      )
    else {
      return nil
    }
    self.store = digitStore
  }

  /// A fresh `Pin1` for one card command, over its own zeroizing copy of
  /// the digits.
  public func issue() -> Pin1 {
    Pin1(owning: ZeroizingDigitStore(bytes: store.bytes))
  }

  /// Non-reversible fingerprint of these digits in the PIN1 role, bound to
  /// no card, for a rejected-PIN memory that lives exactly as long as one
  /// card session.
  public func sessionFingerprint() -> PinFingerprint {
    PinFingerprint.compute(digits: store, serial: nil, role: .pin1)
  }
}
