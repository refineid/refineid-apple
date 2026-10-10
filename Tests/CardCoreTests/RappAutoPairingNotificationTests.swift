// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// What the auto-pairing service tells observers after a reconcile.
@Suite
internal struct RappAutoPairingNotificationTests {
  /// A directory update and a change of pairings are distinct events.
  @Test
  internal func directoryAndPairingChangesAreDistinct() {
    #expect(
      RappAutoPairingService.devicesDidChangeNotification
        != RappAutoPairingService.pairingsDidChangeNotification)
  }
}
