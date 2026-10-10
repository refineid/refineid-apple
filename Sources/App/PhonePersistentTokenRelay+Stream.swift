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
    /// Routes first frames and refuses replayed routing for this listener.
    internal var router = RappSessionRouter()
    /// The announced withdrawal running before the listener goes away.
    internal var withdrawal: Task<Void, Never>?
  }

  /// The stream transport's half of the phone relay.
  ///
  /// The holder is the side whose listener every peer can reach, so it
  /// publishes one session-mode listener under a fresh random name and
  /// waits; a requester dials with a session preamble whose fresh routing
  /// only this holder can resolve to a pairing. The holder never dials.
  @MainActor
  extension PhonePersistentTokenRelay {
    /// The bookkeeping key of the one session listener; never published.
    internal static let sessionListenerKey = "session"

    /// The session record for the pairings in `contexts`.
    private static func sessionRecord(_ contexts: [PhoneStreamPairContext]) -> [String: String] {
      let now = Date()
      return StreamRendezvousName.sessionRecord(
        candidates: contexts.compactMap { context in
          context.candidate(at: now) { pair, time in
            try pair.discoveryHint(unixTimeSeconds: time)
          }
        })
    }

    /// Listens once, under a fresh random name, for every active pair.
    internal func startListening(_ contexts: [PhoneStreamPairContext]) {
      guard !contexts.isEmpty else { return }
      sessionListening.withdrawal?.cancel()
      sessionListening.withdrawal = nil
      if let listener = streamListeners[Self.sessionListenerKey] {
        listener.updateTXTRecord(Self.sessionRecord(contexts))
      } else {
        sessionListening.router = RappSessionRouter()
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
          txtRecord: Self.sessionRecord(contexts))
      }
      startHintRotation()
    }

    /// Announces that this holder stopped serving, then stops listening
    /// (RAPP v26.10.10 §4.5): open sessions close with
    /// `service_withdrawn`, no connection is accepted, and the listener
    /// publishes the withdrawn record for a few seconds before it goes.
    internal func withdrawService(then tearDown: @escaping @MainActor () -> Void) {
      guard let listener = streamListeners[Self.sessionListenerKey],
        let instance = listener.registeredName
      else {
        tearDown()
        return
      }
      stopHintRotation()
      sessionListening.withdrawal?.cancel()
      let closing = coordinator
      let contexts = PhoneStreamPairContext.resolveAll(vault: vault)
      sessionListening.withdrawal = Task { [weak self] in
        await closing?.closeServiceWithdrawn()
        let now = Date()
        let record = StreamRendezvousName.withdrawnRecord(
          candidates: contexts.compactMap { context in
            context.candidate(at: now) { pair, time in
              try pair.withdrawalHint(instance: instance, unixTimeSeconds: time)
            }
          })
        if !record.isEmpty {
          listener.updateTXTRecord(record)
          try? await Task.sleep(
            for: .seconds(Int(StreamRendezvousName.withdrawalAnnouncementSeconds)))
        }
        guard !Task.isCancelled else { return }
        self?.sessionListening.withdrawal = nil
        tearDown()
      }
    }

    /// The bookkeeping keys the given pairs need: the session listener
    /// whenever any pair is active.
    internal func streamKeys(for contexts: [PhoneStreamPairContext]) -> Set<String> {
      contexts.isEmpty ? [] : [Self.sessionListenerKey]
    }

    /// Stops listeners no longer in `keys`.
    internal func pruneStreamTransports(keeping keys: Set<String>) {
      for (key, listener) in streamListeners where !keys.contains(key) {
        listener.cancel()
        streamListeners.removeValue(forKey: key)
        if key == Self.sessionListenerKey { stopHintRotation() }
      }
    }

    /// Stops moving the session listener's hints.
    internal func stopHintRotation() {
      sessionListening.hintRotation?.cancel()
      sessionListening.hintRotation = nil
    }

    /// Republishes the hints at every window boundary while listening.
    private func startHintRotation() {
      stopHintRotation()
      sessionListening.hintRotation = Task { [weak self] in
        while !Task.isCancelled {
          let window = TimeInterval(StreamRendezvousName.hintEpochSeconds)
          let elapsed = Date().timeIntervalSince1970.truncatingRemainder(dividingBy: window)
          try? await Task.sleep(for: .seconds(window - elapsed))
          guard !Task.isCancelled, let self,
            let listener = streamListeners[Self.sessionListenerKey]
          else { return }
          listener.updateTXTRecord(
            Self.sessionRecord(PhoneStreamPairContext.resolveAll(vault: vault)))
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
      if coordinator != nil || sessionListening.withdrawal != nil {
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
      #if DEBUG
        print(
          "[stream-holder] frame \(frame.count) bytes, session \(coordinator != nil)")
        fflush(stdout)
      #endif
      if sessionListening.awaitingPreamble {
        sessionListening.awaitingPreamble = false
        let contexts = PhoneStreamPairContext.resolveAll(vault: vault)
        let route = sessionListening.router.route(
          transportProfile: rappStreamProfileName(), preamble: frame,
          records: contexts.map(\.pairRecord))
        guard case .session(let index) = route, contexts.indices.contains(index) else {
          listener.disconnect()
          return
        }
        let matched = contexts[index]
        PairLastUse.markUsed(pairID: matched.pairRecord.metadata().pairId, at: Date())
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
  }
#endif
