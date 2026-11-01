// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The PIN 1, PIN 2 and PUK lengths the card in session accepts, under
/// the numbering they were mapped by.
///
/// The card's EF.AOD lists each password object's length range (FINEID
/// S4-1 v4.2 §8.1.5; FINEID S4-2 v4.0 §4.6.10 and §4.7.10) and is the
/// authority. A listed range is used as the card lists it, within the
/// lengths its role type can carry (`Pin1` and `Pin2` 4-12 digits, `Puk`
/// 8-12). A credential the card does not list takes the FINEID bounds
/// (FINEID S4-1 v4.2 §4.1: PIN 1 4-12 digits, PIN 2 6-12, PUK 8-12).
///
/// Produced by `CardOperations.readCardPinLengths()` where PINs are set
/// -- activation, change and reset -- never on the signing or login
/// paths. The change and unblock operations take it, address the card
/// under its numbering, and refuse an entry outside its ranges before
/// any command. It describes one card session; a new session reads it
/// again.
public struct CardPinLengths: Equatable, Sendable {
  /// One credential's lengths: what the card lists, and what an entry
  /// is checked against.
  public struct CredentialLengths: Equatable, Sendable {
    /// The range the card lists; nil when it lists none, or its entry
    /// did not decode, and the FINEID bounds apply.
    public let listed: PasswordLengthRange?

    /// The lengths an entry may have.
    ///
    /// The card's range within the lengths the role type carries, or
    /// the FINEID bounds when the card lists nothing. Nil when the
    /// card's range shares no length with what the role type carries,
    /// and no entry is accepted.
    public let accepted: PasswordLengthRange?

    fileprivate init(
      listed: PasswordLengthRange?,
      capacity: PasswordLengthRange,
      fallback: PasswordLengthRange
    ) {
      self.listed = listed
      accepted = listed.map { $0.intersection(capacity) } ?? fallback
    }

    /// Whether an entry of `digitCount` digits is accepted.
    public func accepts(digitCount: Int) -> Bool {
      accepted?.contains(digitCount) ?? false
    }
  }

  /// Shortest PIN 2 under the FINEID bounds (FINEID S4-1 v4.2 §4.1),
  /// the fallback when the card lists none.
  internal static let fineidPin2MinimumDigitCount = 6

  /// The numbering the lengths were mapped by, and the operations
  /// taking them address the card under.
  public let numbering: CredentialReferenceSet

  /// PIN 1's lengths.
  public let pin1: CredentialLengths

  /// PIN 2's lengths.
  public let pin2: CredentialLengths

  /// The PUK's lengths.
  public let puk: CredentialLengths

  private init(
    numbering: CredentialReferenceSet,
    listing: (CredentialRole) -> PasswordLengthRange?
  ) {
    let pinCapacity = Self.range(Pin1.minimumDigitCount, Pin1.maximumDigitCount)
    let pukCapacity = Self.range(Puk.minimumDigitCount, Puk.maximumDigitCount)
    self.numbering = numbering
    pin1 = CredentialLengths(
      listed: listing(.pin1),
      capacity: pinCapacity,
      fallback: Self.range(Pin1.minimumDigitCount, Pin1.maximumDigitCount))
    pin2 = CredentialLengths(
      listed: listing(.pin2),
      capacity: pinCapacity,
      fallback: Self.range(Self.fineidPin2MinimumDigitCount, Pin2.maximumDigitCount))
    puk = CredentialLengths(
      listed: listing(.puk),
      capacity: pukCapacity,
      fallback: pukCapacity)
  }

  /// Lengths for a card that lists none: every credential takes its
  /// FINEID bounds.
  public static func notListed(numbering: CredentialReferenceSet) -> Self {
    Self(numbering: numbering) { _ in nil }
  }

  /// Maps EF.AOD's password objects onto PIN 1, PIN 2 and the PUK.
  ///
  /// An object maps by the reference `numbering` gives the credential,
  /// with or without the specific-reference bit. Objects under other
  /// references are not consulted, and a credential listed more than
  /// once is not listed.
  internal static func mapping(
    _ directory: AuthenticationObjectDirectory?,
    numbering: CredentialReferenceSet
  ) -> Self {
    Self(numbering: numbering) { role in
      let expected = numbering.reference(for: role) | FineidValues.specificReferenceBit
      let matching = (directory?.passwords ?? []).filter { object in
        object.reference | FineidValues.specificReferenceBit == expected
      }
      return matching.count == 1 ? matching.first?.lengths : nil
    }
  }

  /// A range from constants that always admit a length.
  private static func range(_ minimum: Int, _ maximum: Int) -> PasswordLengthRange {
    guard let range = PasswordLengthRange(minimum: minimum, maximum: maximum) else {
      preconditionFailure("the length bounds admit a length")
    }
    return range
  }

  /// The lengths of `role`.
  public func lengths(for role: CredentialRole) -> CredentialLengths {
    switch role {
    case .pin1:
      pin1

    case .pin2:
      pin2

    case .puk:
      puk
    }
  }

  /// Refuses an entry for `role` whose length the card does not accept.
  internal func check(_ role: CredentialRole, digitCount: Int) throws {
    guard lengths(for: role).accepts(digitCount: digitCount) else {
      throw CardOperationError.pinLengthRefused(role)
    }
  }
}
