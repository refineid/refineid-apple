// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation

  /// The phone's pairing offer as its GATT server serves it (RAPP v26.11.8
  /// §4.2, Bootstrap Read Flow item 1, "Busy Refusal" item 2).
  internal struct BluetoothPairingOffer: Sendable {
    /// The bootstrap answer of the moment: the offer, or `pairing-busy`.
    internal let bootstrap: @Sendable () -> Data?
    /// Whether the offer could admit a CPace step 1 now.
    internal let admitsAttempt: @Sendable () -> Bool
    /// Which connection the offer serves, across both transports.
    internal let claim: PairingConnectionClaim
  }
#endif
