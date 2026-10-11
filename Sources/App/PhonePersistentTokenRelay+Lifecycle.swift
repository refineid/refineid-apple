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
        return !streamListeners.isEmpty
      #else
        return relay != nil
      #endif
    }

    // MARK: Functions

    /// Stops advertising without asking the holder to pair again.
    ///
    /// The pairing remains. A card that comes back listens again.
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

    /// Drops the listener and any open session, leaving the reconnect
    /// policy as the caller set it.
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
    }

    /// Hands the advertisement to a pairing ceremony until it ends.
    internal func suspendForPairing() {
      isPairing = true
      let closing = coordinator
      coordinator = nil
      relay?.cancel()
      relay = nil
      #if REFINEID_STREAM_TRANSPORT
        for listener in streamListeners.values {
          listener.cancel()
        }
        streamListeners.removeAll()
        stopHintRotation()
        sessionListening.withdrawal?.cancel()
        sessionListening.withdrawal = nil
        activeStreamListener = nil
      #endif
      connectionID = nil
      isActivelyConnected = false
      Task { await closing?.close() }
    }

    /// Serves the paired computers again once the ceremony has ended.
    internal func resumeAfterPairing() {
      isPairing = false
      start()
    }

    /// Cleans up the active coordinator and connection state while keeping the
    /// stream listener active on the same bound port.
    internal func handleConnectionClosed() {
      let closingCoordinator = coordinator
      coordinator = nil
      dispatcher = nil
      activeStreamListener = nil
      connectionID = nil
      preCoordinatorFrames.removeAll(keepingCapacity: false)
      frameDelivery.reset()
      isActivelyConnected = false
      Task { await closingCoordinator?.transportClosed() }
      if isPairing || !hasUsablePair() {
        tearDownTransport()
      }
    }

    /// Tears down the closed connection and listens again, yielding
    /// immediately for the nearby relay and pausing between stream dial
    /// attempts.
    internal func handleTransportClosed(redialDelayMilliseconds: Int) {
      let closingCoordinator = coordinator
      coordinator = nil
      dispatcher = nil
      relay = nil
      frameDelivery.reset()
      #if REFINEID_STREAM_TRANSPORT
        for listener in streamListeners.values {
          listener.cancel()
        }
        streamListeners.removeAll()
        stopHintRotation()
        sessionListening.withdrawal?.cancel()
        sessionListening.withdrawal = nil
        activeStreamListener = nil
      #endif
      connectionID = nil
      preCoordinatorFrames.removeAll(keepingCapacity: false)
      isActivelyConnected = false
      Task { await closingCoordinator?.transportClosed() }
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
  }
#endif
