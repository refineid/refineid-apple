// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What the custodian tells its requester about the card (RAPP v26.10.21
/// §8.4), and when the word changes.
///
/// A card is present while the phone can serve one (a reader card or a
/// primed near-field card) and the card has not just failed to answer.
/// An operation that ends without the card answering is the custodian's
/// own evidence that it cannot serve right now: the card is reported
/// absent, and present again only once the holder couples or primes a
/// card, or a card answers.
internal struct CustodianCardReport: Equatable {
  /// The word a transition sends.
  internal enum Word: Equatable {
    case present
    case absent
  }

  /// Whether a reader card or a primed card is available at all.
  internal private(set) var servable: Bool

  /// Whether the last card operation was answered; false after one ended
  /// without the card, until a card is coupled again.
  internal private(set) var answered = true

  /// What the requester is told now.
  internal var present: Bool { servable && answered }

  internal init(servable: Bool) {
    self.servable = servable
  }

  /// The word to send when it changed from `before` to `after`.
  private static func change(from before: Bool, to after: Bool) -> Word? {
    guard before != after else { return nil }
    return after ? .present : .absent
  }

  /// A reader card arrived or left, or a prime was stored or cleared;
  /// the word to send, or nil when it is unchanged.
  ///
  /// A card that is servable again was coupled or primed by the holder,
  /// which answers the last failure.
  internal mutating func availabilityChanged(servable: Bool) -> Word? {
    let before = present
    self.servable = servable
    if servable {
      answered = true
    }
    return Self.change(from: before, to: present)
  }

  /// An operation ended without the card answering; the word to send,
  /// or nil when it is unchanged.
  internal mutating func operationEndedUnattended() -> Word? {
    let before = present
    answered = false
    return Self.change(from: before, to: present)
  }

  /// The card answered an operation; the word to send, or nil when it
  /// is unchanged.
  internal mutating func cardAnswered() -> Word? {
    let before = present
    answered = true
    return Self.change(from: before, to: present)
  }
}
