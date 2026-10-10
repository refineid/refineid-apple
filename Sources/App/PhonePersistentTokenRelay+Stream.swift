// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD && REFINEID_STREAM_TRANSPORT
  import CardCore
  import Foundation
  import RappEngine

  /// The one session listener's state between dials.
  internal struct SessionListening {
    /// Moves the listener's rotating hints to each new window.
    internal var hintRotation: Task<Void, Never>?
    /// Whether the connected dialer has yet to present its session
    /// preamble; its first frame must name an active pairing.
    internal var awaitingPreamble = false
  }

  /// The stream transport's half of the phone relay.
  ///
  /// The holder is the side whose listener every peer can reach, so it
  /// publishes one session-mode listener under a fresh random name and
  /// waits; a requester dials with its pair's session preamble, which says
  /// which pairing arrived. Pairs with explicit endpoints are dialed
  /// instead.
  @MainActor
  extension PhonePersistentTokenRelay {
    /// The bookkeeping key of the one session listener; never published.
    internal static let sessionListenerKey = "session"

    /// Listens once for every listen-mode pair and dials pairs with
    /// explicit endpoints.
    internal func startListening(_ contexts: [PhoneStreamPairContext]) {
      for context in contexts where !context.streamEndpoints.isEmpty {
        streamContexts[context.key] = context
        if streamDialers[context.key] != nil || coordinator != nil {
          continue
        }
        let dialer = StreamRelaySession(
          endpointLiterals: context.streamEndpoints,
          preamble: context.sessionPreamble
        ) { [weak self] event in
          Task { @MainActor in
            self?.receiveDialerEvent(event, from: context.key)
          }
        }
        streamDialers[context.key] = dialer
        dialer.start()
      }
      let listening = contexts.filter(\.streamEndpoints.isEmpty)
      guard !listening.isEmpty else { return }
      let tokens = listening.map(\.rendezvousToken)
      if let listener = streamListeners[Self.sessionListenerKey] {
        listener.updateTXTRecord(
          StreamRendezvousName.sessionRecord(rendezvousTokens: tokens, at: Date()))
      } else {
        let listener = StreamRelayListener { [weak self] event in
          Task { @MainActor in
            self?.receiveStream(event)
          }
        }
        streamListeners[Self.sessionListenerKey] = listener
        #if DEBUG
          print("[stream-holder] listening in session mode")
          fflush(stdout)
        #endif
        listener.start(
          displayName: StreamRendezvousName.ephemeralName(),
          txtRecord: StreamRendezvousName.sessionRecord(rendezvousTokens: tokens, at: Date()))
      }
      startHintRotation(tokens)
    }

    /// The bookkeeping keys the given pairs need: one per dialed pair and
    /// the session listener for every listening pair.
    internal func streamKeys(for contexts: [PhoneStreamPairContext]) -> Set<String> {
      var keys = Set(contexts.filter { !$0.streamEndpoints.isEmpty }.map(\.key))
      if contexts.contains(where: \.streamEndpoints.isEmpty) {
        keys.insert(Self.sessionListenerKey)
      }
      return keys
    }

    /// Stops listeners and dialers no longer in `keys`.
    internal func pruneStreamTransports(keeping keys: Set<String>) {
      for (key, listener) in streamListeners where !keys.contains(key) {
        listener.cancel()
        streamListeners.removeValue(forKey: key)
        streamContexts.removeValue(forKey: key)
        if key == Self.sessionListenerKey { stopHintRotation() }
      }
      for (key, dialer) in streamDialers where !keys.contains(key) {
        dialer.cancel()
        streamDialers.removeValue(forKey: key)
        streamContexts.removeValue(forKey: key)
      }
    }

    /// Stops moving the session listener's hints.
    internal func stopHintRotation() {
      sessionListening.hintRotation?.cancel()
      sessionListening.hintRotation = nil
    }

    /// Republishes the hints at every window boundary while listening.
    private func startHintRotation(_ tokens: [Data]) {
      stopHintRotation()
      sessionListening.hintRotation = Task { [weak self] in
        while !Task.isCancelled {
          let window = TimeInterval(StreamRendezvousName.hintEpochSeconds)
          let elapsed = Date().timeIntervalSince1970.truncatingRemainder(dividingBy: window)
          try? await Task.sleep(for: .seconds(window - elapsed))
          guard !Task.isCancelled,
            let listener = self?.streamListeners[Self.sessionListenerKey]
          else { return }
          listener.updateTXTRecord(
            StreamRendezvousName.sessionRecord(rendezvousTokens: tokens, at: Date()))
        }
      }
    }

    private func receiveStream(_ event: StreamRelayEvent) {
      guard let listener = streamListeners[Self.sessionListenerKey] else { return }
      switch event {
      case .connected:
        handleStreamConnected(on: listener)
      case .frame(let frame):
        handleStreamFrame(frame, from: listener)
      case .closed:
        handleStreamClosed(from: listener)
      }
    }

    private func handleStreamConnected(on listener: StreamRelayListener) {
      if coordinator != nil {
        #if DEBUG
          print("[stream-holder] already connected to a peer, disconnecting incoming")
          fflush(stdout)
        #endif
        listener.disconnect()
        return
      }
      activeStreamListener = listener
      sessionListening.awaitingPreamble = true
      connectionID = UUID()
      lastPeerContactDate = Date()
      #if DEBUG
        print("[stream-holder] a dialer arrived")
        fflush(stdout)
      #endif
    }

    /// Routes a dial by its session preamble; an arrival naming no active
    /// pairing is closed without touching stored state (discovery
    /// hierarchy §4.3).
    private func handleStreamFrame(_ frame: Data, from listener: StreamRelayListener) {
      guard activeStreamListener === listener,
        let currentConnectionID = connectionID
      else { return }
      lastPeerContactDate = Date()
      #if DEBUG
        print(
          "[stream-holder] frame \(frame.count) bytes, session \(coordinator != nil)")
        fflush(stdout)
      #endif
      if sessionListening.awaitingPreamble {
        sessionListening.awaitingPreamble = false
        guard
          let matched = StreamSessionRouting.route(
            frame, among: PhoneStreamPairContext.resolveAll(vault: vault),
            preamble: \.sessionPreamble)
        else {
          listener.disconnect()
          return
        }
        establishStream(
          connectionID: currentConnectionID, pair: matched.pairRecord, listener: listener)
      } else if let coordinator {
        deliverInOrder { await coordinator.receive(frame) }
      } else if preCoordinatorFrames.count < Self.maximumPreCoordinatorFrames {
        preCoordinatorFrames.append(frame)
      } else {
        listener.disconnect()
      }
    }

    private func handleStreamClosed(from listener: StreamRelayListener) {
      #if DEBUG
        print("[stream-holder] receiveStream .closed event")
        fflush(stdout)
      #endif
      guard activeStreamListener === listener else { return }
      activeStreamListener = nil
      if listener.isListening {
        handleConnectionClosed()
      } else {
        handleTransportClosed(
          redialDelayMilliseconds: Self.streamRedialDelayMilliseconds
        )
      }
    }

    private func establishStream(
      connectionID: UUID,
      pair: RappPairRecord,
      listener: StreamRelayListener
    ) {
      guard self.connectionID == connectionID, coordinator == nil else { return }

      let transport = RappClosureFrameTransport(
        sender: { [weak listener] frame in
          guard let listener else {
            throw StreamRelayTransportError.notConnected
          }
          try listener.send(frame)
        },
        closer: { [weak listener] in listener?.disconnect() }
      )
      establishCoordinator(
        connectionID: connectionID,
        pair: pair,
        transport: transport
      ) { [weak listener] in
        listener?.disconnect()
      }
    }

    private func receiveDialerEvent(_ event: StreamRelayEvent, from key: String) {
      guard let dialer = streamDialers[key],
        let context = streamContexts[key]
      else { return }
      switch event {
      case .connected:
        handleDialerConnected(on: dialer, context: context)
      case .frame(let frame):
        handleDialerFrame(frame, from: dialer)
      case .closed:
        handleDialerClosed(from: dialer, key: key)
      }
    }

    private func handleDialerConnected(
      on dialer: StreamRelaySession,
      context: PhoneStreamPairContext
    ) {
      if coordinator != nil {
        #if DEBUG
          print(
            "[stream-holder] already connected to a peer, "
              + "cancelling dialer")
          fflush(stdout)
        #endif
        dialer.cancel()
        streamDialers.removeValue(forKey: context.key)
        return
      }
      activeStreamDialer = dialer
      let currentConnectionID = UUID()
      connectionID = currentConnectionID
      lastPeerContactDate = Date()
      #if DEBUG
        print("[stream-holder] dialer connected")
        fflush(stdout)
      #endif
      let transport = RappClosureFrameTransport(
        sender: { [weak dialer] frame in
          guard let dialer else {
            throw StreamRelayTransportError.notConnected
          }
          try await dialer.send(frame)
        },
        closer: { [weak dialer] in dialer?.cancel() }
      )
      establishCoordinator(
        connectionID: currentConnectionID,
        pair: context.pairRecord,
        transport: transport
      ) { [weak dialer] in
        dialer?.cancel()
      }
    }

    private func handleDialerFrame(
      _ frame: Data,
      from dialer: StreamRelaySession
    ) {
      guard activeStreamDialer === dialer,
        connectionID != nil
      else { return }
      lastPeerContactDate = Date()
      #if DEBUG
        print(
          "[stream-holder] dialer received frame \(frame.count) bytes, "
            + "session \(coordinator != nil)")
        fflush(stdout)
      #endif
      if let coordinator {
        deliverInOrder { await coordinator.receive(frame) }
      } else if preCoordinatorFrames.count < Self.maximumPreCoordinatorFrames {
        preCoordinatorFrames.append(frame)
      } else {
        dialer.cancel()
      }
    }

    private func handleDialerClosed(from dialer: StreamRelaySession, key: String) {
      #if DEBUG
        print("[stream-holder] dialer .closed event")
        fflush(stdout)
      #endif
      if activeStreamDialer === dialer {
        activeStreamDialer = nil
      }
      streamDialers.removeValue(forKey: key)
      handleTransportClosed(
        redialDelayMilliseconds: Self.streamRedialDelayMilliseconds
      )
    }
  }
#endif
