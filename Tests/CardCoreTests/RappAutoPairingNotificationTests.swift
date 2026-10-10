// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// When the auto-pairing service reports a change of pairings.
@Suite
internal struct RappAutoPairingNotificationTests {
  private enum Fixture {
    static let first = Data(repeating: 1, count: 16)
    static let second = Data(repeating: 2, count: 16)
  }

  /// A directory update and a change of pairings are distinct events.
  @Test
  internal func directoryAndPairingChangesAreDistinct() {
    #expect(
      RappAutoPairingService.devicesDidChangeNotification
        != RappAutoPairingService.pairingsDidChangeNotification)
  }

  /// The same pairings before and after are no change.
  @Test
  internal func unchangedPairingsAreNoChange() {
    #expect(!RappPairingSnapshot.pairs([Fixture.first]).differs(from: .pairs([Fixture.first])))
  }

  /// An added or removed pairing is a change.
  @Test
  internal func addedOrRemovedPairingIsAChange() {
    #expect(
      RappPairingSnapshot.pairs([Fixture.first]).differs(
        from: .pairs([Fixture.first, Fixture.second])))
    #expect(RappPairingSnapshot.pairs([Fixture.first]).differs(from: .pairs([])))
  }

  /// A read that failed on either side counts as a change.
  @Test
  internal func unreadablePairingsAreAChange() {
    #expect(RappPairingSnapshot.unreadable.differs(from: .pairs([Fixture.first])))
    #expect(RappPairingSnapshot.pairs([Fixture.first]).differs(from: .unreadable))
  }
}
