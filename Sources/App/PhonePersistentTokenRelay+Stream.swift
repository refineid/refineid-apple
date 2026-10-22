// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD && REFINEID_STREAM_TRANSPORT
  import CardCore
  import Foundation
  import os
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
    /// The instance name the listener asked Bonjour for.
    internal var requestedName: String?
  }

  /// The stream transport's half of the phone relay.
  ///
  /// The holder is the side whose listener every peer can reach, so it
  /// publishes one session-mode listener under a fresh random name and
  /// waits; a requester dials with a session preamble whose fresh routing
  /// only this holder can resolve to a pairing. The holder never dials.
  @MainActor
  extension PhonePersistentTokenRelay {
    /// How long the stream transport pauses before re-listening after a
    /// connection closes.
    internal static let streamRedialDelayMilliseconds = 100

    /// How long the open session must have been idle before a dialer on a
    /// different pairing may displace it (R-59): long enough that f, the
    /// Mac and Windows stop stealing each other's session between
    /// operations, short enough that a genuinely free phone hands over.
    internal static let crossPeerHoldSeconds: Int64 = 5

    /// The bookkeeping key of the one session listener; never published.
    internal static let sessionListenerKey = "session"

    /// How long a withdrawal waits for the open session's close notice
    /// before it announces itself anyway.
    private static let closeAllowanceMilliseconds = 500

    /// Whether a dialer whose first frame is `preamble` may take the open
    /// session's place; asked on the listener's queue.
    nonisolated private static func admitsReplacement(
      preamble: Data,
      routing: OSAllocatedUnfairLock<(records: [RappPairRecord], router: RappSessionRouter)>,
      serving: OSAllocatedUnfairLock<(pairing: Data?, idleSince: ContinuousClock.Instant?)>,
      profile: String,
      holdSeconds: Int64
    ) -> Bool {
      // Only a session preamble naming a served pairing displaces a
      // session (RAPP §2.2.1, §8.4); a stranger or a pairing attempt
      // displaces nothing.
      let (served, router) = routing.withLock { $0 }
      let route = router.route(transportProfile: profile, preamble: preamble, records: served)
      guard case .session(let index) = route, served.indices.contains(index) else {
        #if DEBUG
          DevErrorLog.report(
            route == .pairing
              ? "dial refused: pairing attempt while a session is open"
              : "dial refused: preamble matches no pairing, a session is open",
            source: .app)
        #endif
        return false
      }
      let incoming = served[index].metadata().pairId
      let (pairing, idleSince) = serving.withLock { $0 }
      // A busy session is never displaced; the requester's own app and
      // token extension hand an idle one over at once, and another
      // requester waits out the hold (R-59).
      let verdict = HolderSessionAdmission.decide(
        incoming: incoming, pairing: pairing, idleSince: idleSince, now: .now,
        hold: .seconds(holdSeconds))
      #if DEBUG
        if !verdict.admits {
          DevErrorLog.report("dial refused: \(verdict)", source: .app)
        }
      #endif
      return verdict.admits
    }

    /// The session record for the pairings in `contexts`: their discovery
    /// hints (transport hierarchy §4.3).
    ///
    /// A pairing this holder forgot keeps its hint until its close reaches the
    /// requester (RAPP v26.10.22 §4.6 item 2).
    private func sessionRecord(_ contexts: [PhoneStreamPairContext]) -> [String: String] {
      let now = Date()
      return StreamRendezvousName.sessionRecord(
        candidates: contexts.compactMap { context in
          context.candidate(at: now) { pair, time in
            try pair.discoveryHint(unixTimeSeconds: time)
          }
        })
    }

    /// Republishes the session record, after a pairing ended or a window
    /// moved.
    internal func refreshSessionRecord() {
      guard let listener = streamListeners[Self.sessionListenerKey] else { return }
      RappPairRevocation.expireRevocationNotices(in: vault, clock: RappPlatformClock())
      listener.updateTXTRecord(sessionRecord(PhoneStreamPairContext.resolveAll(vault: vault)))
    }

    /// Listens once, under a fresh random name, for every active pair.
    internal func startListening(_ contexts: [PhoneStreamPairContext]) {
      guard !contexts.isEmpty else { return }
      sessionListening.withdrawal?.cancel()
      sessionListening.withdrawal = nil
      let records = contexts.map(\.pairRecord)
      replacementRouting.withLock { $0.records = records }
      if let listener = streamListeners[Self.sessionListenerKey] {
        listener.updateTXTRecord(sessionRecord(contexts))
      } else {
        sessionListening.router = RappSessionRouter()
        replacementRouting.withLock { $0.router = RappSessionRouter() }
        let routing = replacementRouting
        let serving = sessionServing
        let holdSeconds = Self.crossPeerHoldSeconds
        let profile = rappStreamProfileName()
        let listener = StreamRelayListener(
          admitsReplacement: { preamble in
            Self.admitsReplacement(
              preamble: preamble, routing: routing, serving: serving,
              profile: profile, holdSeconds: holdSeconds)
          },
          onEvent: { [weak self] event in
            Task { @MainActor in
              self?.receiveStream(event)
            }
          })
        streamListeners[Self.sessionListenerKey] = listener
        #if DEBUG
          print("[stream-holder] listening in session mode")
          fflush(stdout)
        #endif
        let name = StreamRendezvousName.ephemeralName()
        sessionListening.requestedName = name
        listener.start(displayName: name, txtRecord: sessionRecord(contexts))
      }
      startHintRotation()
    }

    /// Announces that this holder stopped serving, then stops serving.
    ///
    /// RAPP v26.10.22 §4.5: the open session closes with
    /// `service_withdrawn` on whichever transport carries it, no
    /// connection is accepted, Bluetooth stops advertising, and the stream
    /// listener publishes the withdrawn record for a few seconds before it
    /// goes. Bluetooth carries no withdrawal marker (§4.5 item 5).
    internal func withdrawService(then tearDown: @escaping @MainActor () -> Void) {
      let listener = streamListeners[Self.sessionListenerKey]
      let instance = listener?.registeredName ?? sessionListening.requestedName
      stopHintRotation()
      sessionListening.withdrawal?.cancel()
      let closing = coordinator
      let contexts = PhoneStreamPairContext.resolveAll(vault: vault)
      let allowance = Duration.milliseconds(Self.closeAllowanceMilliseconds)
      sessionListening.withdrawal = Task { [weak self] in
        // The close goes first, but a slow peer does not hold back the
        // announcement every other paired computer is waiting for.
        await withTaskGroup(of: Void.self) { group in
          group.addTask { await closing?.closeServiceWithdrawn() }
          group.addTask {
            try? await Task.sleep(for: allowance)
          }
          await group.next()
          group.cancelAll()
        }
        self?.stopBluetoothServing()
        if let listener, let instance {
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
          guard !Task.isCancelled, let self else { return }
          refreshSessionRecord()
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
      // A dialer arriving while a Bluetooth session is open waits for its
      // preamble: the one-session gate decides on it (CC-67).
      if case .bluetooth = servedTransport, sessionListening.withdrawal == nil {
        activeStreamListener = listener
        sessionListening.awaitingPreamble = true
        return
      }
      if coordinator != nil || sessionListening.withdrawal != nil {
        #if DEBUG
          print("[stream-holder] already connected to a peer, disconnecting incoming")
          fflush(stdout)
          DevErrorLog.report(
            coordinator == nil
              ? "dial refused: service is being withdrawn"
              : "dial refused: a session is still open",
            source: .app)
        #endif
        listener.disconnect()
        return
      }
      activeStreamListener = listener
      sessionListening.awaitingPreamble = true
      #if DEBUG
        print("[stream-holder] a dialer arrived")
        fflush(stdout)
      #endif
    }

    /// Routes a dial by its session preamble; an arrival naming no active
    /// pairing is closed without touching stored state (discovery
    /// hierarchy §4.3).
    private func handleStreamFrame(_ frame: Data, from listener: StreamRelayListener) {
      guard activeStreamListener === listener else { return }
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
          #if DEBUG
            DevErrorLog.report(
              route == .pairing
                ? "dial refused: pairing preamble on the session listener"
                : "dial refused: preamble matches no pairing",
              source: .app)
          #endif
          listener.disconnect()
          return
        }
        let matched = contexts[index]
        guard admitSession(for: matched.pairRecord.metadata().pairId) else {
          listener.disconnect()
          return
        }
        PairLastUse.markUsed(pairID: matched.pairRecord.metadata().pairId, at: Date())
        let routedConnectionID = UUID()
        connectionID = routedConnectionID
        activeStreamListener = listener
        establishStream(
          connectionID: routedConnectionID, pair: matched.pairRecord, listener: listener)
      } else if servedTransport != .stream {
        return
      } else if let coordinator {
        deliverInOrder { await coordinator.receive(frame) }
      } else if preCoordinatorFrames.count < Self.maximumPreCoordinatorFrames {
        preCoordinatorFrames.append(frame)
      } else {
        #if DEBUG
          DevErrorLog.report("dial dropped: too many frames before the session", source: .app)
        #endif
        listener.disconnect()
      }
    }

    private func handleStreamClosed(from listener: StreamRelayListener) {
      #if DEBUG
        print("[stream-holder] receiveStream .closed event")
        fflush(stdout)
      #endif
      guard activeStreamListener === listener else { return }
      guard servedTransport == .stream else {
        // A dialer that left before its preamble opened no session.
        activeStreamListener = nil
        sessionListening.awaitingPreamble = false
        if !listener.isListening {
          handleTransportClosed(redialDelayMilliseconds: Self.streamRedialDelayMilliseconds)
        }
        return
      }
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
      servedTransport = .stream
      // The listener carries one connection at a time, so a session that
      // ends after another took its place must not cut the newcomer.
      let transport = RappClosureFrameTransport(
        sender: { [weak listener] frame in
          guard let listener else {
            throw StreamRelayTransportError.notConnected
          }
          try listener.send(frame)
        },
        closer: { [weak self, weak listener] in
          await MainActor.run {
            guard self?.connectionID == connectionID else { return }
            listener?.disconnect()
          }
        }
      )
      establishCoordinator(
        connectionID: connectionID,
        pair: pair,
        transportProfile: rappStreamProfileName(),
        transport: transport
      ) { [weak listener] in
        listener?.disconnect()
      }
      if coordinator == nil {
        servedTransport = nil
      }
    }
  }
#endif
