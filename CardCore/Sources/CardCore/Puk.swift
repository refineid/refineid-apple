// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// A validated PUK value with single-use ownership.
///
/// The PUK is not a PIN: it never authorises an operation on the user's
/// behalf. It resets a blocked PIN's retry counter while setting a new
/// value (RESET RETRY COUNTER, FINEID S1 v4.2 §3.5.4). The eight-digit
/// activation code printed in a pre-2026 issuance letter is presented
/// through this type too: on those cards it is the PUK.
///
/// The PUK spends its own retry counter. A wrong entry counts down, and
/// exhausting it is terminal for the card - only the issuer can recover
/// it - so callers hold the retry floor against the PUK's counter, not
/// the target PIN's. No cache path exists.
public struct Puk: ~Copyable {
  /// Shortest PUK on the supported cards: seven-digit activation PUKs
  /// exist in the field.
  public static let minimumDigitCount: Int = 7

  /// Longest PUK on the supported cards.
  public static let maximumDigitCount: Int = 8

  private let store: ZeroizingDigitStore

  /// Validates and takes ownership of the entered digits.
  ///
  /// Refuses any input that is not 7-8 ASCII digits; there is no other
  /// way to construct a `Puk`.
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

  /// Non-reversible fingerprint of this PUK bound to one card and the
  /// PUK role, for the rejected-PIN memory.
  ///
  /// Reading the fingerprint does not consume the value: it is not a
  /// transmission.
  public borrowing func fingerprint(boundTo serial: ChipSerial) -> PinFingerprint {
    PinFingerprint.compute(digits: store, serial: serial, role: .puk)
  }

  /// Consumes this PUK for exactly one card command.
  ///
  /// After this call the value no longer exists; a retry, replay, or
  /// resend needs a fresh user entry by construction.
  public consuming func consumeForSingleTransmission() -> PukTransmission {
    PukTransmission(store: store)
  }
}
