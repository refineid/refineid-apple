// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// PIN 1 the holder entered, bound to the card it was entered for: one the
/// card accepted, or one no card ever received because the card did not
/// come (RAPP v26.10.29 §8.4 item 1, §11 item 2).
///
/// `Card` names the card; the phone binds the value to the card's
/// certificate fingerprint. The value ends when another card, or no card,
/// is named in its place, and on `clear()`, which the owner calls when the
/// card refuses it and when the holder forgets everything. The owner keeps
/// it in memory only, never in storage; the digits live only in the
/// entry's zeroizing store.
public struct CardBoundPin1<Card: Equatable> {
  /// One held value and the card it belongs to.
  private struct Entry {
    let pin1: Pin1Entry
    let card: Card
  }

  private var entry: Entry?

  /// Holds nothing.
  public init() {
    // Starts empty: no card has been given a PIN 1 yet.
  }

  /// The PIN 1 held for `card`, the card present now.
  ///
  /// Nil when none is held for it, or no card can be named; a value held
  /// for another card is forgotten.
  public mutating func current(card: Card?) -> Pin1Entry? {
    guard let entry else { return nil }
    guard entry.card == card else {
      clear()
      return nil
    }
    return entry.pin1
  }

  /// Holds `pin1` for `card`, replacing any value held before.
  public mutating func hold(_ pin1: Pin1Entry, card: Card) {
    entry = Entry(pin1: pin1, card: card)
  }

  /// Forgets the held value unless it belongs to `card`, the card present
  /// now.
  public mutating func keep(onlyFor card: Card?) {
    if entry?.card != card {
      entry = nil
    }
  }

  /// Forgets the held value.
  public mutating func clear() {
    entry = nil
  }
}
