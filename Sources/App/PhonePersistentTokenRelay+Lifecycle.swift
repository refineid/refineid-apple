// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation
  import RappEngine

  @MainActor
  extension PhonePersistentTokenRelay {
    // MARK: Computed Properties

    internal var isServing: Bool {
      sessionListener != nil || bluetoothServer != nil
    }

    // MARK: Functions

    /// Stops advertising without telling the paired computers.
    internal func stopServing() {
      tearDownTransport()
    }

    /// Stops serving because the holder switched remote access off.
    ///
    /// Paired computers learn it at once instead of waiting out a lost
    /// advertisement. The pairing remains.
    internal func withdrawAndStopServing() {
      withdrawService { [weak self] in self?.tearDownTransport() }
    }

    /// Drops the listener, the Bluetooth server and every open session,
    /// leaving the reconnect policy as the caller set it.
    internal func tearDownTransport() {
      stopListening()
      sessionListening.withdrawal?.cancel()
      sessionListening.withdrawal = nil
      stopBluetoothServing()
      for session in sessions.values {
        session.close()
      }
      HolderSummons.shared.cancelAll()
      Task { await RappNearFieldSessionHolder.shared.closeSession(.servingStopped) }
    }

    internal func hasUsablePair() -> Bool {
      guard let active = try? vault.activePairIDs() else { return false }
      return !active.isEmpty
    }

    /// Ends every established session over `pairID` with `pairing_revoked`
    /// as the pairing is forgotten (RAPP v26.10.29 §4.6 item 1); false when
    /// no session over `pairID` is open or no close left, so the pairing is
    /// kept forgotten for its next session.
    internal func closeForRevocation(pairID: Data) async -> Bool {
      let closing = sessions.values
        .filter { $0.pairID == pairID && $0.isEstablished }
        .map(\.coordinator)
      var told = false
      for coordinator in closing {
        let left = await coordinator.closePairingRevoked()
        told = told || left
      }
      return told
    }
  }
#endif
