// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineIDTestHost

/// When a card that stays without an identity starts to warn.
@Suite
@MainActor
internal struct SettleDeadlineTests {
  private enum Fixture {
    static let limit: Duration = .milliseconds(80)
    static let poll: Duration = .milliseconds(10)
    static let patience = 100
  }

  private final class Changes {
    var values: [Bool] = []
  }

  private static func wait(until condition: () -> Bool) async throws {
    for _ in 0..<Fixture.patience where !condition() {
      try await Task.sleep(for: Fixture.poll)
    }
  }

  /// A card that stays without an identity warns after the limit.
  @Test
  internal func warnsAfterTheLimit() async throws {
    let changes = Changes()
    let deadline = SettleDeadline(limit: Fixture.limit) { changes.values.append($0) }
    deadline.cardWithoutIdentity(true)
    #expect(!deadline.hasExpired)
    try await Self.wait { deadline.hasExpired }
    #expect(changes.values == [true])
  }

  /// A card that gets its identity in time never warns.
  @Test
  internal func settlingInTimeNeverWarns() async throws {
    let changes = Changes()
    let deadline = SettleDeadline(limit: Fixture.limit) { changes.values.append($0) }
    deadline.cardWithoutIdentity(true)
    deadline.cardWithoutIdentity(false)
    try await Task.sleep(for: Fixture.limit * 2)
    #expect(!deadline.hasExpired)
    #expect(changes.values.isEmpty)
  }

  /// The warning clears as soon as the state ends.
  @Test
  internal func warningClearsWhenTheStateEnds() async throws {
    let changes = Changes()
    let deadline = SettleDeadline(limit: Fixture.limit) { changes.values.append($0) }
    deadline.cardWithoutIdentity(true)
    try await Self.wait { deadline.hasExpired }
    deadline.cardWithoutIdentity(false)
    #expect(!deadline.hasExpired)
    #expect(changes.values == [true, false])
  }
}
