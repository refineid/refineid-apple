// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  extension RappPairingCoordinator {
    /// Whether the transport carries the offer as the custodian's first
    /// frame rather than on a characteristic the requester reads.
    internal var servesOfferAsFrame: Bool {
      transportProfile != RappBleGattProfile.name
    }

    /// The custodian's bootstrap answer now, for the BLE characteristic: the
    /// offer while it can admit an attempt, `pairing-busy` while it cannot
    /// (RAPP v26.10.29 §4.2, Bootstrap Read Flow item 1).
    nonisolated public func bootstrapAnswer() throws -> Data {
      try bridge.bootstrapBytes(nowMonotonicMs: clock.monotonicMilliseconds())
    }

    /// The `pairing-busy` for a pairing connection the custodian cannot
    /// carry beside the one it serves, or nil once its offer is spent
    /// (RAPP v26.10.29 §4.2, "Busy Refusal").
    nonisolated public func busyAnswer() -> Data? {
      let now = clock.monotonicMilliseconds()
      return try? bridge.busyBytes(
        nowMonotonicMs: now, spacingWaitMs: preAuthentication.waitMs(nowMonotonicMs: now))
    }

    /// Whether a CPace step 1 arriving now could be admitted; a BLE
    /// custodian refuses one that could not with the application error
    /// (RAPP v26.10.29 §4.2, "Busy Refusal" item 2).
    nonisolated public func admitsAttempt() -> Bool {
      bridge.admitsAttempt(nowMonotonicMs: clock.monotonicMilliseconds())
    }
  }
#endif
