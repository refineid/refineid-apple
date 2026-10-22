// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation
  import RappEngine

  @MainActor
  extension PhonePersistentTokenRelay {
    // MARK: Computed Properties

    internal var isServing: Bool {
      #if REFINEID_STREAM_TRANSPORT
        return !streamListeners.isEmpty || bluetoothServer != nil
      #else
        return relay != nil
      #endif
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
      #if REFINEID_STREAM_TRANSPORT
        withdrawService { [weak self] in self?.tearDownTransport() }
      #else
        tearDownTransport()
      #endif
    }

    /// Drops the listener, the Bluetooth server and any open session,
    /// leaving the reconnect policy as the caller set it.
    private func tearDownTransport() {
      #if REFINEID_STREAM_TRANSPORT
        for listener in streamListeners.values {
          listener.cancel()
        }
        streamListeners.removeAll()
        stopHintRotation()
        sessionListening.withdrawal?.cancel()
        sessionListening.withdrawal = nil
        activeStreamListener = nil
        servedTransport = nil
        stopBluetoothServing()
      #else
        relay?.cancel()
        relay = nil
      #endif
      if let coord = coordinator {
        Task { await coord.transportClosed() }
        Task { await coord.close() }
      }
      coordinator = nil
      dispatcher = nil
      connectionID = nil
      preCoordinatorFrames.removeAll(keepingCapacity: false)
      frameDelivery.reset()
      isActivelyConnected = false
      sessionServing.withLock { $0 = (nil, nil) }
      HolderSummons.shared.cancelAll()
    }

    /// Cleans up the open session while keeping the stream listener on the
    /// same port and the Bluetooth server serving; a stream connection that
    /// still awaits its preamble beside a closed Bluetooth session stays.
    internal func handleConnectionClosed() {
      let closingCoordinator = coordinator
      #if REFINEID_STREAM_TRANSPORT
        if servedTransport == .stream {
          activeStreamListener = nil
        }
        servedTransport = nil
      #endif
      coordinator = nil
      dispatcher = nil
      connectionID = nil
      preCoordinatorFrames.removeAll(keepingCapacity: false)
      frameDelivery.reset()
      isActivelyConnected = false
      sessionServing.withLock { $0 = (nil, nil) }
      HolderSummons.shared.cancelAll()
      Task { await closingCoordinator?.transportClosed() }
      if !hasUsablePair() {
        tearDownTransport()
        return
      }
      #if REFINEID_STREAM_TRANSPORT
        suspendStreamWhenIdle()
      #endif
    }

    /// Tears down the stream listener after it failed and listens again.
    ///
    /// The nearby relay listens again at once, the stream after a pause.
    /// A session over Bluetooth is not the stream's and stays.
    internal func handleTransportClosed(redialDelayMilliseconds: Int) {
      #if REFINEID_STREAM_TRANSPORT
        let keepsSession: Bool
        if case .bluetooth = servedTransport {
          keepsSession = true
        } else {
          keepsSession = false
        }
      #else
        let keepsSession = false
      #endif
      if !keepsSession {
        let closingCoordinator = coordinator
        coordinator = nil
        dispatcher = nil
        frameDelivery.reset()
        connectionID = nil
        preCoordinatorFrames.removeAll(keepingCapacity: false)
        isActivelyConnected = false
        sessionServing.withLock { $0 = (nil, nil) }
        HolderSummons.shared.cancelAll()
        Task { await closingCoordinator?.transportClosed() }
      }
      relay = nil
      #if REFINEID_STREAM_TRANSPORT
        if !keepsSession { servedTransport = nil }
        for listener in streamListeners.values {
          listener.cancel()
        }
        streamListeners.removeAll()
        stopHintRotation()
        sessionListening.withdrawal?.cancel()
        sessionListening.withdrawal = nil
        activeStreamListener = nil
      #endif
      Task { @MainActor in
        if redialDelayMilliseconds > 0 {
          try? await Task.sleep(for: .milliseconds(redialDelayMilliseconds))
        } else {
          await Task.yield()
        }
        self.start()
      }
    }

    internal func hasUsableSelectedPair() -> Bool {
      (try? PhoneProxyPairSelection.resolveSelectedPair(vault: vault)) != nil
    }

    internal func hasUsablePair() -> Bool {
      guard let active = try? vault.activePairIDs() else { return false }
      return !active.isEmpty
    }

    /// Ends the open session with `pairing_revoked` as the pairing it runs
    /// over is forgotten (RAPP v26.10.22 §4.6 item 1); false when no session
    /// over `pairID` is open or the close did not leave, so the pairing is
    /// kept forgotten for its next session.
    internal func closeForRevocation(pairID: Data) async -> Bool {
      guard let coordinator, activePairID == pairID else { return false }
      return await coordinator.closePairingRevoked()
    }
  }
#endif
