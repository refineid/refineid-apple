// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import RappEngine

/// When the identity a phone confirmed stops being offered to local
/// consumers (RAPP v26.10.22 §8.4 item 3).
///
/// A session whose `card.status` names the card present keeps the offer.
/// Once no session is open, or the phone reports absence, the offer lapses
/// after the grace with no report of the card present in that time; such a
/// report confirms it again. A report of absence is never a different
/// card: only a session naming another card ends the offer at once, which
/// the owner decides by fingerprint, as it does a forget or a revocation.
internal struct RemoteIdentityOffer: Equatable, Sendable {
  /// What a session's `card.status` does to the offer.
  internal enum Response: Equatable, Sendable {
    /// No card can answer: the offer stays for the grace.
    case absent
    /// Another card than the one offered is present: withdraw at once and
    /// read the new one (§8.4 item 2).
    case differentCard
    /// A card is present and none is offered: read its certificate.
    case nothingOffered
    /// The card offered is present: the offer stands.
    case offeredCard
  }

  /// The phone's word on the offered card.
  internal enum Standing: Equatable, Sendable {
    /// An open session reports the card present.
    case confirmed
    /// No open session has reported the card present since this instant.
    case unconfirmed(since: ContinuousClock.Instant)
  }

  /// How long an unconfirmed offer stays (§8.4 item 3).
  internal static var grace: Duration { .milliseconds(rappIdentityOfferGraceMs()) }

  internal private(set) var standing: Standing

  /// The instant the offer lapses, or nil while it is confirmed.
  internal var lapsesAt: ContinuousClock.Instant? {
    guard case .unconfirmed(let since) = standing else { return nil }
    return since + Self.grace
  }

  /// An offer no session has confirmed since `instant`.
  internal init(unconfirmedSince instant: ContinuousClock.Instant) {
    standing = .unconfirmed(since: instant)
  }

  /// Takes a session's `card.status` at `instant`, for an offer of the
  /// card whose certificate has the fingerprint `offered`, or of none.
  internal mutating func receive(
    _ status: RappCardStatus,
    offered: RappCertificateFingerprint?,
    at instant: ContinuousClock.Instant
  ) -> Response {
    switch status {
    case .absent:
      loseConfirmation(at: instant)
      return .absent

    case .present(let named):
      standing = .confirmed
      guard let offered else { return .nothingOffered }
      return offered == named ? .offeredCard : .differentCard
    }
  }

  /// The session ended, or it reported absence, at `instant`; an offer
  /// already unconfirmed keeps the instant it lost its confirmation.
  internal mutating func loseConfirmation(at instant: ContinuousClock.Instant) {
    guard case .confirmed = standing else { return }
    standing = .unconfirmed(since: instant)
  }

  /// Whether the offer has lapsed at `instant`.
  internal func hasLapsed(at instant: ContinuousClock.Instant) -> Bool {
    guard let lapsesAt else { return false }
    return instant >= lapsesAt
  }
}
