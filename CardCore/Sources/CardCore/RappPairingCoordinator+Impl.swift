// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  extension RappPairingCoordinator {
    /// Watchdog windows matching the engine's deadlines (RAPP v26.10.9 §3.3).
    private enum Window {
      static let attemptMilliseconds: UInt64 = 5_000
      static let handshakeMilliseconds: UInt64 = 10_000
      static let confirmationMilliseconds: UInt64 = 10_000
      static let nanosecondsPerMillisecond: UInt64 = 1_000_000
    }

    // MARK: Public API

    /// Arms the offer lifetime; the custodian calls this when it starts
    /// showing the code, the requester when it starts connecting.
    public func start() {
      guard state == .offer else { return }
      armDeadline(at: offerDeadlineMilliseconds)
    }

    /// Installs the transport for the next connection after a failed
    /// custodian attempt restored the offer.
    @discardableResult
    public func replaceTransport(_ replacement: any RappFrameTransport) -> Bool {
      guard state == .offer else { return false }
      transport = replacement
      return true
    }

    /// Starts the ceremony once the candidate's connection is open and its
    /// pairing preamble has been exchanged.
    ///
    /// A custodian serves its offer as the first frame on a frame
    /// transport; a requester without an offer waits for that frame. At most
    /// one connection per 500 ms reaches the offer (RAPP v26.10.9 §3.3.8).
    public func transportConnected() async {
      guard state == .offer else {
        await fail(.protocolFailure)
        return
      }
      do {
        switch role {
        case .requester:
          guard bridge != nil else {
            state = .requesterAwaitingOffer
            return
          }
          try await beginRequesterCpace(now: clock.monotonicMilliseconds())

        case .proxy:
          guard preAuthentication.admit(nowMonotonicMs: clock.monotonicMilliseconds()) else {
            await transport.close()
            continuation.yield(.offerRestored)
            return
          }
          try live().beginCpace(
            candidateId: candidateID,
            randomBytes64: try entropy.cpaceRandom(),
            nowMonotonicMs: clock.monotonicMilliseconds())
          state = .custodianAwaitingStepOne
          if servesOfferAsFrame {
            try await transport.send(try live().encodedOffer())
          }
        }
      } catch {
        await handle(error)
      }
    }

    /// Consumes one complete frame received from the transport.
    public func receive(_ frame: Data) async {
      do {
        try await receiveFrame(frame)
      } catch {
        await handle(error)
      }
    }

    /// Reacts to the transport closing before the ceremony finished.
    public func transportClosed() async {
      switch state {
      case .completed, .closed:
        return

      case .offer:
        if role == .requester { await fail(.transportFailure) }

      default:
        await abandonCandidate(.transportFailure)
      }
    }

    /// Ends the pairing attempt at local request.
    public func close() async {
      await fail(.localRequest)
    }

    // MARK: Frame Dispatch

    private func receiveFrame(_ frame: Data) async throws {
      let now = clock.monotonicMilliseconds()
      switch state {
      case .requesterAwaitingOffer:
        self.bridge = try RappPairingBridge.bootstrapOffer(
          encodedOffer: frame, transportProfile: transportProfile, pairingCode: pairingCode,
          startedAtMonotonicMs: now)
        try await beginRequesterCpace(now: now)

      case .requesterAwaitingStepTwo:
        try live().readCpaceFrame(bytes: frame, nowMonotonicMs: now)
        let stepThree = try live().writeCpaceFrame(nowMonotonicMs: now)
        let handshakeOne = try live().writeHandshakeFrame(nowMonotonicMs: now)
        state = .requesterAwaitingHandshakeTwo
        armDeadline(after: Window.handshakeMilliseconds)
        try await transport.send(stepThree)
        try await transport.send(handshakeOne)

      case .requesterAwaitingHandshakeTwo:
        try live().readHandshakeFrame(bytes: frame, nowMonotonicMs: now)
        let handshakeThree = try live().writeHandshakeFrame(nowMonotonicMs: now)
        try enterPairingChannel(now: now)
        let hello = try live().sendHello(
          displayName: displayName, platform: platform, nowMonotonicMs: now)
        state = .awaitingPeerHello
        try await transport.send(handshakeThree)
        try await transport.send(hello)

      case .custodianAwaitingStepOne:
        try live().readCpaceFrame(bytes: frame, nowMonotonicMs: now)
        let stepTwo = try live().writeCpaceFrame(nowMonotonicMs: now)
        state = .custodianAwaitingStepThree
        armDeadline(after: Window.attemptMilliseconds)
        try await transport.send(stepTwo)

      case .custodianAwaitingStepThree:
        try live().readCpaceFrame(bytes: frame, nowMonotonicMs: now)
        state = .custodianAwaitingHandshakeOne
        armDeadline(after: Window.handshakeMilliseconds)

      case .custodianAwaitingHandshakeOne:
        try live().readHandshakeFrame(bytes: frame, nowMonotonicMs: now)
        let handshakeTwo = try live().writeHandshakeFrame(nowMonotonicMs: now)
        state = .custodianAwaitingHandshakeThree
        try await transport.send(handshakeTwo)

      case .custodianAwaitingHandshakeThree:
        try live().readHandshakeFrame(bytes: frame, nowMonotonicMs: now)
        try enterPairingChannel(now: now)
        state = .awaitingPeerHello

      case .awaitingPeerHello:
        try await receivePeerHello(frame, now: now)

      case .awaitingPeerConfirmation:
        try await receivePeerConfirmation(frame, now: now)

      case .offer, .completed, .closed:
        await fail(.protocolFailure)
      }
    }

    /// The requester's first CPace message, once its offer is known.
    private func beginRequesterCpace(now: UInt64) async throws {
      try live().beginCpace(
        candidateId: candidateID, randomBytes64: try entropy.cpaceRandom(), nowMonotonicMs: now)
      let stepOne = try live().writeCpaceFrame(nowMonotonicMs: now)
      state = .requesterAwaitingStepTwo
      try await transport.send(stepOne)
    }

    /// The ceremony's engine, which every step after the offer needs.
    private func live() throws -> RappPairingBridge {
      guard let bridge else { throw RappBindingError.WrongPhase }
      return bridge
    }

    private func enterPairingChannel(now: UInt64) throws {
      guard try live().handshakeComplete(nowMonotonicMs: now) else {
        throw RappBindingError.ProtocolFailure
      }
      try live().enterConfirmation(nowMonotonicMs: now)
      armDeadline(after: Window.confirmationMilliseconds)
    }

    /// The requester introduces itself first; the custodian answers with its
    /// own introduction and the grant.
    private func receivePeerHello(_ frame: Data, now: UInt64) async throws {
      let peer = Peer(try live().receiveHello(bytes: frame, nowMonotonicMs: now))
      continuation.yield(.peerIntroduced(peer))
      switch role {
      case .requester:
        state = .awaitingPeerConfirmation

      case .proxy:
        let hello = try live().sendHello(
          displayName: displayName, platform: platform, nowMonotonicMs: now)
        let granted = profiles.filter { (peer.requestedProfiles ?? []).contains($0) }
        let grant = try live().sendConfirmation(grantedProfiles: granted, nowMonotonicMs: now)
        state = .awaitingPeerConfirmation
        try await transport.send(hello)
        try await transport.send(grant)
      }
    }

    /// Completes the grant exchange and stores the pairing.
    ///
    /// The requester echoes the custodian's grant; the custodian accepts the
    /// echo. Either way both sets are now equal.
    private func receivePeerConfirmation(_ frame: Data, now: UInt64) async throws {
      let granted = try live().receiveConfirmation(bytes: frame, nowMonotonicMs: now)
      if role == .requester {
        let echo = try live().sendConfirmation(grantedProfiles: granted, nowMonotonicMs: now)
        try await transport.send(echo)
      }
      try await finish(now: now)
    }

    // MARK: Finish / Fail

    private func finish(now: UInt64) async throws {
      let record = try live().finishPairing(
        createdAtMs: clock.wallMilliseconds(), nowMonotonicMs: now)
      do {
        try record.persistDeviceOnly(vault: vault)
      } catch {
        await fail(.persistenceFailure)
        return
      }
      state = .completed
      cancelDeadline()
      continuation.yield(.paired(PairSummary(record.metadata())))
      continuation.finish()
      await transport.close()
    }

    private func handle(_ error: any Error) async {
      switch error {
      case RappBindingError.OfferExpired:
        await fail(.offerExpired)

      case RappBindingError.AttemptsExhausted:
        await fail(.attemptsExhausted)

      default:
        await abandonCandidate(.protocolFailure)
      }
    }

    /// Ends the connected attempt; a custodian with attempts left keeps its
    /// offer and waits for the next connection.
    private func abandonCandidate(_ reason: CloseReason) async {
      guard state != .completed, state != .closed else { return }
      if bridge?.candidateFailed(nowMonotonicMs: clock.monotonicMilliseconds()) == true {
        state = .offer
        await transport.close()
        armDeadline(at: offerDeadlineMilliseconds)
        continuation.yield(.offerRestored)
        return
      }
      await fail(bridge?.attemptsExhausted() == true ? .attemptsExhausted : reason)
    }

    internal func fail(_ reason: CloseReason) async {
      guard state != .closed, state != .completed else { return }
      state = .closed
      cancelDeadline()
      bridge?.cancelPairing()
      await transport.close()
      continuation.yield(.closed(reason))
      continuation.finish()
    }

    // MARK: Deadlines

    private func armDeadline(after window: UInt64) {
      armDeadline(at: Self.deadline(startedAt: clock.monotonicMilliseconds(), lifetime: window))
    }

    /// One watchdog at a time: the latest phase's deadline replaces the last.
    private func armDeadline(at instant: UInt64) {
      cancelDeadline()
      let now = clock.monotonicMilliseconds()
      let remaining = instant > now ? instant - now : 0
      let (nanoseconds, overflow) = remaining.multipliedReportingOverflow(
        by: Window.nanosecondsPerMillisecond)
      let delay = overflow ? UInt64.max : nanoseconds
      deadlineTask = Task { [weak self] in
        do { try await Task.sleep(nanoseconds: delay) } catch { return }
        guard !Task.isCancelled, let self else { return }
        await deadlineElapsed()
      }
    }

    private func cancelDeadline() {
      deadlineTask?.cancel()
      deadlineTask = nil
    }

    private func deadlineElapsed() async {
      switch state {
      case .completed, .closed:
        return

      case .offer:
        await fail(.offerExpired)

      default:
        await abandonCandidate(.offerExpired)
      }
    }
  }
#endif
