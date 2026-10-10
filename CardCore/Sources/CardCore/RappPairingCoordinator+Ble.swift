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

    /// The offer the custodian serves through its transport's bootstrap: the
    /// BLE characteristic, or the first stream frame (RAPP v26.10.9 §4.2).
    public func bootstrapOffer() throws -> Data {
      guard let bridge else { throw RappBindingError.WrongPhase }
      return try bridge.encodedOffer()
    }
  }
#endif
