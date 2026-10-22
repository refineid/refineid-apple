// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import RappEngine
import Testing

@testable import RefineID

/// When the identity a phone confirmed stays offered (RAPP v26.10.22 §8.4
/// item 3).
@Suite
internal struct RemoteIdentityOfferTests {
  /// The smallest step of the clock the grace runs on.
  private static let tick = Duration.milliseconds(1)

  /// The fingerprint of the card offered.
  private static func offeredCard() throws -> RappCertificateFingerprint {
    try #require(RappCertificateFingerprint(certificate: Data("offered card certificate".utf8)))
  }

  /// The fingerprint of a card other than the one offered.
  private static func otherCard() throws -> RappCertificateFingerprint {
    try #require(RappCertificateFingerprint(certificate: Data("other card certificate".utf8)))
  }

  /// An offer that lost its confirmation at `start`.
  private static func unconfirmed(at start: ContinuousClock.Instant) -> RemoteIdentityOffer {
    RemoteIdentityOffer(unconfirmedSince: start)
  }

  @Test("An unconfirmed offer lapses once the grace has run, not before")
  internal func lapsesAfterTheGrace() {
    let start = ContinuousClock.now
    let offer = Self.unconfirmed(at: start)
    #expect(!offer.hasLapsed(at: start))
    #expect(!offer.hasLapsed(at: start + RemoteIdentityOffer.grace - Self.tick))
    #expect(offer.hasLapsed(at: start + RemoteIdentityOffer.grace))
    #expect(offer.lapsesAt == start + RemoteIdentityOffer.grace)
  }

  @Test("The grace is the engine's 120 seconds")
  internal func graceIsTheEngines() {
    #expect(RemoteIdentityOffer.grace == .milliseconds(rappIdentityOfferGraceMs()))
  }

  @Test("A card reported present keeps the offer for as long as the session says so")
  internal func presentConfirms() throws {
    let offered = try Self.offeredCard()
    let start = ContinuousClock.now
    var offer = Self.unconfirmed(at: start)
    #expect(
      offer.receive(.present(offered), offered: offered, at: start)
        == .offeredCard)
    #expect(offer.standing == .confirmed)
    #expect(offer.lapsesAt == nil)
    #expect(!offer.hasLapsed(at: start + RemoteIdentityOffer.grace + RemoteIdentityOffer.grace))
  }

  @Test("A report of absence starts the grace and is never another card")
  internal func absenceStartsTheGrace() throws {
    let offered = try Self.offeredCard()
    let start = ContinuousClock.now
    var offer = Self.unconfirmed(at: start)
    _ = offer.receive(.present(offered), offered: offered, at: start)
    let lost = start + RemoteIdentityOffer.grace
    #expect(offer.receive(.absent, offered: offered, at: lost) == .absent)
    #expect(offer.standing == .unconfirmed(since: lost))
    #expect(!offer.hasLapsed(at: lost + RemoteIdentityOffer.grace - Self.tick))
    #expect(offer.hasLapsed(at: lost + RemoteIdentityOffer.grace))
  }

  @Test("Another loss keeps the instant the confirmation was first lost")
  internal func repeatedLossKeepsTheFirstInstant() throws {
    let offered = try Self.offeredCard()
    let start = ContinuousClock.now
    var offer = Self.unconfirmed(at: start)
    _ = offer.receive(.present(offered), offered: offered, at: start)
    offer.loseConfirmation(at: start)
    _ = offer.receive(.absent, offered: offered, at: start + Self.tick)
    offer.loseConfirmation(at: start + Self.tick)
    #expect(offer.standing == .unconfirmed(since: start))
  }

  @Test("A card reported present again restarts the grace from the next loss")
  internal func presenceRestartsTheGrace() throws {
    let offered = try Self.offeredCard()
    let start = ContinuousClock.now
    var offer = Self.unconfirmed(at: start)
    let back = start + RemoteIdentityOffer.grace - Self.tick
    #expect(
      offer.receive(.present(offered), offered: offered, at: back)
        == .offeredCard)
    #expect(!offer.hasLapsed(at: start + RemoteIdentityOffer.grace))
    let lostAgain = back + Self.tick
    offer.loseConfirmation(at: lostAgain)
    #expect(!offer.hasLapsed(at: lostAgain + RemoteIdentityOffer.grace - Self.tick))
    #expect(offer.hasLapsed(at: lostAgain + RemoteIdentityOffer.grace))
  }

  @Test("Another card present is told apart from the card offered, and from none")
  internal func differentCard() throws {
    let offered = try Self.offeredCard()
    let other = try Self.otherCard()
    let start = ContinuousClock.now
    var offer = Self.unconfirmed(at: start)
    #expect(
      offer.receive(.present(other), offered: offered, at: start)
        == .differentCard)
    #expect(offer.receive(.present(other), offered: nil, at: start) == .nothingOffered)
    #expect(offer.receive(.absent, offered: nil, at: start) == .absent)
  }
}
