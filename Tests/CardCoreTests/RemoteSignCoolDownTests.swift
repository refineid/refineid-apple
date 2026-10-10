// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

@Suite
internal struct RemoteSignCoolDownTests {
  private enum Fixture {
    static let initial = RemoteSignCoolDown.initialPause
    static let ceiling = RemoteSignCoolDown.ceiling
    static let moment: TimeInterval = 1

    static func coolDown() -> RemoteSignCoolDown {
      let suite = "fi.refineid.tests.coolDown.\(UUID().uuidString)"
      return RemoteSignCoolDown(defaultsSuite: suite)
    }
  }

  /// Nothing is refused before anything ended unattended.
  @Test
  internal func startsOpen() {
    #expect(!Fixture.coolDown().refuses(at: Date()))
  }

  /// An unattended ending refuses requests for the initial pause only.
  @Test
  internal func unattendedEndingPauses() {
    let coolDown = Fixture.coolDown()
    let now = Date()
    coolDown.record(.unattended, at: now)
    #expect(coolDown.refuses(at: now.addingTimeInterval(Fixture.initial - Fixture.moment)))
    #expect(!coolDown.refuses(at: now.addingTimeInterval(Fixture.initial)))
    let until = coolDown.pausedUntil(at: now)?.timeIntervalSince(now) ?? 0
    #expect(abs(until - Fixture.initial) < Fixture.moment)
  }

  /// Consecutive unattended endings double the pause up to the ceiling.
  @Test
  internal func pauseDoublesToCeiling() {
    #expect(RemoteSignCoolDown.pause(after: 1) == Fixture.initial)
    #expect(RemoteSignCoolDown.pause(after: 2) == Fixture.initial * 2)
    #expect(RemoteSignCoolDown.pause(after: 3) == Fixture.initial * 4)
    #expect(RemoteSignCoolDown.pause(after: 40) == Fixture.ceiling)
  }

  /// The second consecutive ending pauses twice as long as the first.
  @Test
  internal func consecutiveEndingsGrow() {
    let coolDown = Fixture.coolDown()
    let now = Date()
    coolDown.record(.unattended, at: now)
    let next = now.addingTimeInterval(Fixture.initial + Fixture.moment)
    coolDown.record(.unattended, at: next)
    #expect(coolDown.refuses(at: next.addingTimeInterval(Fixture.initial)))
    #expect(!coolDown.refuses(at: next.addingTimeInterval(Fixture.initial * 2)))
  }

  /// Endings that arrive inside a pause do not lengthen it.
  @Test
  internal func endingsInsideAPauseDoNotGrowIt() {
    let coolDown = Fixture.coolDown()
    let now = Date()
    coolDown.record(.unattended, at: now)
    coolDown.record(.unattended, at: now.addingTimeInterval(Fixture.moment))
    #expect(!coolDown.refuses(at: now.addingTimeInterval(Fixture.initial)))
  }

  /// An unattended ending long after the last pause ended starts the
  /// count over.
  @Test
  internal func quietPeriodStartsOver() {
    let coolDown = Fixture.coolDown()
    let now = Date()
    coolDown.record(.unattended, at: now)
    let next = now.addingTimeInterval(Fixture.initial + Fixture.moment)
    coolDown.record(.unattended, at: next)
    let later = next.addingTimeInterval(Fixture.initial * 2 + Fixture.ceiling + Fixture.moment)
    coolDown.record(.unattended, at: later)
    #expect(!coolDown.refuses(at: later.addingTimeInterval(Fixture.initial)))
  }

  /// A signature clears the pause and the count.
  @Test
  internal func signatureResets() {
    let coolDown = Fixture.coolDown()
    let now = Date()
    coolDown.record(.unattended, at: now)
    coolDown.record(.unattended, at: now)
    coolDown.record(.signed, at: now)
    #expect(!coolDown.refuses(at: now))
    coolDown.record(.unattended, at: now)
    #expect(!coolDown.refuses(at: now.addingTimeInterval(Fixture.initial)))
  }

  /// Resuming lets the next request through at once.
  @Test
  internal func resumeClears() {
    let coolDown = Fixture.coolDown()
    let now = Date()
    coolDown.record(.unattended, at: now)
    coolDown.resume()
    #expect(!coolDown.refuses(at: now))
  }

  /// Other failures neither pause nor reset.
  @Test
  internal func otherFailuresAreNeutral() {
    let coolDown = Fixture.coolDown()
    let now = Date()
    coolDown.record(.other, at: now)
    #expect(!coolDown.refuses(at: now))
    coolDown.record(.unattended, at: now)
    coolDown.record(.other, at: now)
    #expect(coolDown.refuses(at: now))
  }
}
