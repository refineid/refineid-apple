// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineID

/// What waits for the first look at the card readers runs once: when the
/// look is taken, or after its bound when the look never comes.
@Suite
@MainActor
internal struct InitialScanGateTests {
  private enum Fixture {
    /// A bound no test reaches.
    static let longBound: Duration = .seconds(30)
    /// A bound a test reaches at once.
    static let shortBound: Duration = .milliseconds(20)
    static let poll: Duration = .milliseconds(10)
    static let patience = 100
  }

  /// How often a waiter ran.
  @MainActor
  private final class Runs {
    var times = 0
  }

  private static func wait(until condition: () -> Bool) async throws {
    for _ in 0..<Fixture.patience where !condition() {
      try await Task.sleep(for: Fixture.poll)
    }
  }

  @Test("A first look that never comes releases the waiter at its bound")
  internal func scanThatNeverCompletes() async throws {
    let gate = InitialScanGate()
    let runs = Runs()
    gate.wait(atMost: Fixture.shortBound) { runs.times += 1 }
    #expect(runs.times == 0)
    try await Self.wait { runs.times == 1 }
    #expect(runs.times == 1)
    #expect(!gate.isComplete, "the look itself is still owed")
  }

  @Test("A first look releases the waiter at once, and only once")
  internal func scanThatCompletes() async throws {
    let gate = InitialScanGate()
    let runs = Runs()
    gate.wait(atMost: Fixture.shortBound) { runs.times += 1 }
    gate.complete()
    #expect(runs.times == 1)
    try await Task.sleep(for: Fixture.shortBound * 2)
    #expect(runs.times == 1, "the bound passing later runs nothing again")

    gate.wait(atMost: Fixture.longBound) { runs.times += 1 }
    #expect(runs.times == 2, "after the look a waiter runs at once")
    gate.complete()
    #expect(runs.times == 2)
  }
}
