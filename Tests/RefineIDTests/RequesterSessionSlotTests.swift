// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineID

/// A computer holds one session with its phone, and dials again only after
/// a wait that grows to a bound (STPA CC-71, CC-d).
@Suite
internal struct RequesterSessionSlotTests {
  /// The smallest step of the clock the waits run on.
  private static let tick = Duration.milliseconds(1)

  /// The doubling the back-off applies.
  private static let growth = 2

  @Test("A session being dialled or open on any transport blocks a second dial")
  internal func oneSessionAcrossTransports() {
    let now = ContinuousClock.now
    var slot = RequesterSessionSlot()
    let first = slot.dial(over: .bluetooth, at: now)
    #expect(first)
    #expect(!slot.mayDial(at: now))
    let whileDialling = slot.dial(over: .stream, at: now)
    #expect(!whileDialling)
    #expect(slot.transport == .bluetooth)
    slot.established()
    #expect(slot.isEstablished)
    let overStream = slot.dial(over: .stream, at: now)
    let overBluetooth = slot.dial(over: .bluetooth, at: now)
    #expect(!overStream)
    #expect(!overBluetooth)
  }

  @Test("Each failed dial waits longer, up to the bound")
  internal func waitGrowsToTheBound() {
    var now = ContinuousClock.now
    var slot = RequesterSessionSlot()
    var previous = Duration.zero
    for _ in 0..<RedialBackoffTests.failuresPastTheBound {
      let dialled = slot.dial(over: .stream, at: now)
      #expect(dialled)
      slot.ended(at: now)
      let wait = (slot.nextDialAt ?? now) - now
      #expect(wait >= previous)
      #expect(wait <= RedialBackoff.longestDelay)
      #expect(!slot.mayDial(at: now + wait - Self.tick))
      #expect(slot.mayDial(at: now + wait))
      previous = wait
      now += wait
    }
    #expect(previous == RedialBackoff.longestDelay)
  }

  @Test("A session that comes up starts the wait over")
  internal func establishedStartsOver() {
    let now = ContinuousClock.now
    var slot = RequesterSessionSlot()
    _ = slot.dial(over: .stream, at: now)
    slot.ended(at: now)
    let first = (slot.nextDialAt ?? now) - now
    let later = now + first
    _ = slot.dial(over: .stream, at: later)
    slot.ended(at: later)
    #expect((slot.nextDialAt ?? later) - later == first * Self.growth)
    let again = later + first * Self.growth
    _ = slot.dial(over: .bluetooth, at: again)
    slot.established()
    #expect(slot.nextDialAt == nil)
    slot.ended(at: again)
    #expect((slot.nextDialAt ?? again) - again == first)
  }

  @Test("A phone newly seen may be dialled at once; letting go frees the slot")
  internal func startOverAndRelease() {
    let now = ContinuousClock.now
    var slot = RequesterSessionSlot()
    _ = slot.dial(over: .stream, at: now)
    slot.ended(at: now)
    #expect(!slot.mayDial(at: now))
    slot.startOver()
    #expect(slot.mayDial(at: now))
    _ = slot.dial(over: .stream, at: now)
    slot.released()
    #expect(slot.state == .empty)
    #expect(slot.mayDial(at: now))
  }
}
