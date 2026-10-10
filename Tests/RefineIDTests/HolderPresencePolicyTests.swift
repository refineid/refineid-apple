// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RefineID

/// When the requester reads and when it withdraws the borrowed identity.
@Suite
internal struct HolderPresencePolicyTests {
  /// With a browser, launch waits for the holder; without one it reads.
  @Test(arguments: [(true, false), (false, true)])
  internal func launchReadsOnlyWithoutABrowser(browses: Bool, reads: Bool) {
    #expect(HolderPresencePolicy.readsAtStart(browsesForPresence: browses) == reads)
  }

  /// A read the browser has not confirmed starts the countdown.
  @Test(arguments: [(false, true), (true, false)])
  internal func unconfirmedReadStartsTheCountdown(seen: Bool, arms: Bool) {
    #expect(HolderPresencePolicy.armsLossHoldAfterRead(holderSeen: seen) == arms)
  }

  /// A loss counts once the holder was seen or an identity is held.
  @Test(arguments: [
    (false, false, false), (true, false, true), (false, true, true), (true, true, true),
  ])
  internal func lossStartsTheCountdown(seen: Bool, held: Bool, arms: Bool) {
    #expect(
      HolderPresencePolicy.armsLossHoldOnLoss(holderSeen: seen, identityHeld: held) == arms)
  }
}
