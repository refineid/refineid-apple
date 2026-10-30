// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation
  import RappEngine

  /// The session listener's state between dials.
  internal struct SessionListening {
    /// Moves the listener's rotating hints to each new window.
    internal var hintRotation: Task<Void, Never>?
    /// The connections that have yet to present their session preamble;
    /// each one's first frame must name an active pairing.
    internal var awaitingPreamble: Set<StreamSessionConnection> = []
    /// Routes first frames and refuses replayed routing for this listener.
    internal var admission = CustodianSessionAdmission()
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
  /// only this holder can resolve to a pairing. Every connection whose
  /// preamble routes opens a session of its own, beside any already open
  /// (RAPP v26.10.29 §2.2.2). The holder never dials.
  @MainActor
  extension PhonePersistentTokenRelay {
    /// How long the stream transport pauses before it listens again after
    /// its listener ended.
    internal static let streamRelistenDelayMilliseconds = 100

    /// How long a withdrawal waits for the open sessions' close notices
    /// before it announces itself anyway.
    private static let closeAllowanceMilliseconds = 500

    /// Closes every one of `coordinators` with `service_withdrawn` at once.
    nonisolated private static func closeServiceWithdrawn(
      _ coordinators: [RappConnectionCoordinator]
    ) async {
      await withTaskGroup(of: Void.self) { group in
        for coordinator in coordinators {
          group.addTask { _ = await coordinator.closeServiceWithdrawn() }
        }
      }
    }

    /// The session record for the pairings in `contexts`: their discovery
    /// hints (transport hierarchy §4.3).
    ///
    /// A pairing this holder forgot keeps its hint until its close reaches the
    /// requester (RAPP v26.10.29 §4.6 item 2).
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
      guard let sessionListener else { return }
      RappPairRevocation.expireRevocationNotices(in: vault, clock: RappPlatformClock())
      let contexts = PhoneStreamPairContext.resolveAll(vault: vault)
      sessionListener.updateTXTRecord(sessionRecord(contexts))
    }

    /// Listens once, under a fresh random name, for every active pair.
    internal func startListening(_ contexts: [PhoneStreamPairContext]) {
      guard !contexts.isEmpty else { return }
      sessionListening.withdrawal?.cancel()
      sessionListening.withdrawal = nil
      sessionListening.admission.records = contexts.map(\.pairRecord)
      if let sessionListener {
        sessionListener.updateTXTRecord(sessionRecord(contexts))
      } else {
        sessionListening.admission.forgetRouted()
        sessionListening.awaitingPreamble.removeAll()
        // One stream carries the listener's events to the main actor in
        // the order the listener reported them: a connection's first
        // frame never overtakes its arrival.
        let (events, sink) = AsyncStream.makeStream(of: StreamSessionListener.Event.self)
        let listener = StreamSessionListener { event in
          sink.yield(event)
          if case .ended = event { sink.finish() }
        }
        sessionListener = listener
        sessionListenerEvents = Task { [weak self] in
          for await event in events {
            self?.receiveStream(event, from: listener)
          }
        }
        #if DEBUG
          HolderTrace.say("stream: listening in session mode")
        #endif
        let name = StreamRendezvousName.ephemeralName()
        sessionListening.requestedName = name
        listener.start(displayName: name, txtRecord: sessionRecord(contexts))
      }
      startHintRotation()
    }

    /// Stops the session listener, closing every stream connection.
    internal func stopListening() {
      sessionListener?.cancel()
      sessionListener = nil
      sessionListening.awaitingPreamble.removeAll()
      stopHintRotation()
    }

    /// Announces that this holder stopped serving, then stops serving.
    ///
    /// RAPP v26.10.29 §4.5: every open session closes with
    /// `service_withdrawn` on whichever transport carries it, no
    /// connection is accepted, Bluetooth stops advertising, and the stream
    /// listener publishes the withdrawn record for a few seconds before it
    /// goes. Bluetooth carries no withdrawal marker (§4.5 item 5).
    internal func withdrawService(then tearDown: @escaping @MainActor () -> Void) {
      let listener = sessionListener
      let instance = listener?.registeredName ?? sessionListening.requestedName
      stopHintRotation()
      sessionListening.withdrawal?.cancel()
      let closing = sessions.values.map(\.coordinator)
      let contexts = PhoneStreamPairContext.resolveAll(vault: vault)
      let allowance = Duration.milliseconds(Self.closeAllowanceMilliseconds)
      sessionListening.withdrawal = Task { [weak self] in
        // The closes go first, but a slow peer does not hold back the
        // announcement every other paired computer is waiting for.
        await withTaskGroup(of: Void.self) { group in
          group.addTask { await Self.closeServiceWithdrawn(closing) }
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

    private func receiveStream(
      _ event: StreamSessionListener.Event, from listener: StreamSessionListener
    ) {
      switch event {
      case .connected(let connection):
        streamConnected(connection, on: listener)

      case .frame(let connection, let frame):
        if sessionListening.awaitingPreamble.remove(connection) != nil {
          routeDial(connection, preamble: frame, on: listener)
        } else {
          session(on: .stream(connection))?.receive(frame)
        }

      case .closed(let connection, _):
        sessionListening.awaitingPreamble.remove(connection)
        session(on: .stream(connection))?.transportClosed()

      case .ended:
        guard listener === sessionListener else { return }
        listenerEnded()
      }
    }

    /// A dialer arrived, and its first frame decides.
    ///
    /// None is taken while service is being withdrawn or the stream is
    /// suspended for the background (CC-68).
    private func streamConnected(
      _ connection: StreamSessionConnection, on listener: StreamSessionListener
    ) {
      guard listener === sessionListener, sessionListening.withdrawal == nil, !streamSuspended
      else {
        #if DEBUG
          DevErrorLog.report(
            "dial refused: \(streamSuspended ? "stream suspended" : "service is being withdrawn")",
            source: .app)
        #endif
        listener.disconnect(connection)
        return
      }
      sessionListening.awaitingPreamble.insert(connection)
    }

    /// Routes a dial by its session preamble; an arrival naming no active
    /// pairing is closed without touching stored state (discovery
    /// hierarchy §4.3).
    private func routeDial(
      _ connection: StreamSessionConnection, preamble: Data, on listener: StreamSessionListener
    ) {
      let contexts = PhoneStreamPairContext.resolveAll(vault: vault)
      sessionListening.admission.records = contexts.map(\.pairRecord)
      let verdict = sessionListening.admission.admit(
        preamble, transportProfile: rappStreamProfileName())
      guard case .open(let index) = verdict else {
        #if DEBUG
          DevErrorLog.report(
            verdict == .refusedPairingAttempt
              ? "dial refused: pairing preamble on the session listener"
              : "dial refused: preamble matches no pairing",
            source: .app)
        #endif
        listener.disconnect(connection)
        return
      }
      let frames = RappClosureFrameTransport(
        sender: { [weak listener] frame in
          guard let listener else { throw StreamRelayTransportError.notConnected }
          try listener.send(frame, on: connection)
        },
        closer: { [weak listener] in listener?.disconnect(connection) })
      let opened = openSession(
        pair: contexts[index].pairRecord, on: .stream(connection),
        transportProfile: rappStreamProfileName(), frames: frames, earlyFrames: [])
      if opened == nil { listener.disconnect(connection) }
    }

    /// The listener failed: its connections closed with it; it listens
    /// again after a pause.
    private func listenerEnded() {
      #if DEBUG
        DevErrorLog.report("stream listener ended; listening again", source: .app)
      #endif
      sessionListener = nil
      sessionListening.awaitingPreamble.removeAll()
      sessionListening.withdrawal?.cancel()
      sessionListening.withdrawal = nil
      stopHintRotation()
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(Self.streamRelistenDelayMilliseconds))
        self.start()
      }
    }
  }
#endif
