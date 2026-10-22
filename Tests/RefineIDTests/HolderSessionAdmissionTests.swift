// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineID

/// The phone serves one session at a time, whatever transport carries the
/// dial (STPA CC-67, R-59).
@Suite
internal struct HolderSessionAdmissionTests {
  /// The cross-peer hold the cases run against.
  private static let hold = Duration.seconds(5)

  /// The smallest step of the clock the hold runs on.
  private static let tick = Duration.milliseconds(1)

  /// The pairing that dials.
  private static let incoming = Data("pairing-incoming".utf8)

  /// Another computer's pairing.
  private static let other = Data("pairing-other-pc".utf8)

  private static func decide(
    pairing: Data?, idleSince: ContinuousClock.Instant?, now: ContinuousClock.Instant
  ) -> HolderSessionAdmission {
    HolderSessionAdmission.decide(
      incoming: incoming, pairing: pairing, idleSince: idleSince, now: now, hold: hold)
  }

  @Test("A dial with no session open is admitted")
  internal func emptySlotAdmits() {
    let now = ContinuousClock.now
    #expect(Self.decide(pairing: nil, idleSince: nil, now: now) == .admit)
  }

  @Test("A busy session is displaced by no one, its own pairing included")
  internal func busySessionIsNeverDisplaced() {
    let now = ContinuousClock.now
    #expect(Self.decide(pairing: Self.incoming, idleSince: nil, now: now) == .refuseBusy)
    #expect(Self.decide(pairing: Self.other, idleSince: nil, now: now) == .refuseBusy)
  }

  @Test("An idle session is handed over to its own pairing at once")
  internal func ownPairingTakesAnIdleSessionAtOnce() {
    let now = ContinuousClock.now
    #expect(Self.decide(pairing: Self.incoming, idleSince: now, now: now) == .admit)
  }

  @Test("Another pairing waits out the hold, then takes the idle session")
  internal func otherPairingWaitsOutTheHold() {
    let idle = ContinuousClock.now
    #expect(
      Self.decide(pairing: Self.other, idleSince: idle, now: idle + Self.hold - Self.tick)
        == .refuseHeld)
    #expect(Self.decide(pairing: Self.other, idleSince: idle, now: idle + Self.hold) == .admit)
  }

  @Test("Only an admission admits")
  internal func onlyAdmitAdmits() {
    #expect(HolderSessionAdmission.admit.admits)
    #expect(!HolderSessionAdmission.refuseBusy.admits)
    #expect(!HolderSessionAdmission.refuseHeld.admits)
  }
}
