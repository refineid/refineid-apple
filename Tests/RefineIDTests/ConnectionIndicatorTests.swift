// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineIDTestHost

/// How the connected indicator follows sessions that open and close.
@Suite
@MainActor
internal struct ConnectionIndicatorTests {
  private enum Fixture {
    static let hold: Duration = .milliseconds(100)
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

  /// An opened session shows at once.
  @Test
  internal func opensAtOnce() {
    let changes = Changes()
    let indicator = ConnectionIndicator(hold: Fixture.hold) { changes.values.append($0) }
    indicator.update(active: true)
    #expect(indicator.isShown)
    #expect(changes.values == [true])
  }

  /// A closed session stops showing after the hold.
  @Test
  internal func closesAfterTheHold() async throws {
    let changes = Changes()
    let indicator = ConnectionIndicator(hold: Fixture.hold) { changes.values.append($0) }
    indicator.update(active: true)
    indicator.update(active: false)
    #expect(indicator.isShown)
    try await Self.wait { !indicator.isShown }
    #expect(!indicator.isShown)
    #expect(changes.values == [true, false])
  }

  /// A session that closes and reopens within the hold never blinks.
  @Test
  internal func reopeningWithinTheHoldDoesNotBlink() async throws {
    let changes = Changes()
    let indicator = ConnectionIndicator(hold: Fixture.hold) { changes.values.append($0) }
    indicator.update(active: true)
    indicator.update(active: false)
    indicator.update(active: true)
    try await Task.sleep(for: Fixture.hold * 2)
    #expect(indicator.isShown)
    #expect(changes.values == [true])
  }

  /// Closing what never opened changes nothing.
  @Test
  internal func closingWhileHiddenChangesNothing() {
    let changes = Changes()
    let indicator = ConnectionIndicator(hold: Fixture.hold) { changes.values.append($0) }
    indicator.update(active: false)
    #expect(!indicator.isShown)
    #expect(changes.values.isEmpty)
  }
}
