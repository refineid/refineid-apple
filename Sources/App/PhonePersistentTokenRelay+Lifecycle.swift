// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation
  import RappEngine

  @MainActor
  extension PhonePersistentTokenRelay {
    // MARK: Computed Properties

    /// Whether a paired requester is online, connected, or was recently in contact.
    internal var isPeerConnectedOrOnline: Bool {
      if isActivelyConnected { return true }
      guard hasUsablePair() else {
        return false
      }
      if hasRecentPeerContact { return true }
      if isPeerOnline || RappAutoPairingService.shared.isAnyPairedPeerOnline { return true }
      return false
    }

    internal var hasRecentPeerContact: Bool {
      guard let lastContact = lastPeerContactDate else { return false }
      return Date().timeIntervalSince(lastContact) < Self.recentContactWindowSeconds
    }

    internal var isServing: Bool {
      #if REFINEID_STREAM_TRANSPORT
        return !streamListeners.isEmpty || !streamDialers.isEmpty
      #else
        return relay != nil
      #endif
    }

    // MARK: Functions

    /// Explicit UI action may call this after the user has corrected local
    /// credentials or deliberately chosen to reconnect.
    ///
    /// It never restores a revoked pair; the vault remains authoritative.
    internal func resumeAfterUserAction() {
      relistenPolicy = .automatic
      start()
    }

    /// Listens again while the policy still allows it, after a card that
    /// can be served has returned.
    internal func resumeServing() {
      guard relistenPolicy == .automatic else { return }
      start()
    }

    /// Stops advertising without asking the holder to pair again.
    ///
    /// The pairing remains. A card that comes back listens again.
    internal func stopServing() {
      tearDownTransport()
    }

    internal func stopListening() {
      relistenPolicy = .explicitUserActionRequired
      tearDownTransport()
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
        for dialer in streamDialers.values {
          dialer.cancel()
        }
        streamDialers.removeAll()
        streamContexts.removeAll()
        activeStreamListener = nil
        activeStreamDialer = nil
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

    internal func suspendForPairing() {
      relistenPolicy = .explicitUserActionRequired
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
        for dialer in streamDialers.values {
          dialer.cancel()
        }
        streamDialers.removeAll()
        streamContexts.removeAll()
        activeStreamListener = nil
        activeStreamDialer = nil
      #endif
      connectionID = nil
      isActivelyConnected = false
      Task { await closing?.close() }
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
      if relistenPolicy != .automatic || !hasUsablePair() {
        relistenPolicy = .explicitUserActionRequired
        tearDownTransport()
      }
    }

    /// Tears down the closed connection and reconnects while automatic,
    /// yielding immediately for the nearby relay and pausing between
    /// stream dial attempts.
    internal func handleTransportClosed(redialDelayMilliseconds: Int) {
      let closingCoordinator = coordinator
      coordinator = nil
      dispatcher = nil
      relay = nil
      frameDelivery.reset()
      #if REFINEID_SLIM_RELAY
        slimSession = nil
        slimProxy = nil
      #endif
      #if REFINEID_STREAM_TRANSPORT
        for listener in streamListeners.values {
          listener.cancel()
        }
        streamListeners.removeAll()
        stopHintRotation()
        streamContexts.removeAll()
        activeStreamListener = nil
      #endif
      connectionID = nil
      preCoordinatorFrames.removeAll(keepingCapacity: false)
      isActivelyConnected = false
      Task { await closingCoordinator?.transportClosed() }
      if !hasUsablePair() {
        relistenPolicy = .explicitUserActionRequired
      }
      guard relistenPolicy == .automatic else { return }
      Task { @MainActor in
        if redialDelayMilliseconds > 0 {
          try? await Task.sleep(for: .milliseconds(redialDelayMilliseconds))
        } else {
          await Task.yield()
        }
        self.start()
      }
    }

    internal func updatePeerOnlineState() {
      let online = RappAutoPairingService.shared.isAnyPairedPeerOnline
      if isPeerOnline != online {
        isPeerOnline = online
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
