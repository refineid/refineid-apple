// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  extension RappPairingCoordinator {
    /// Watchdog windows matching the engine's deadlines (RAPP v26.10.29 §3.3).
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
    /// transport; a requester, which already read the offer, sends CPace
    /// step 1. At most one connection per 500 ms reaches the offer (RAPP
    /// v26.10.29 §3.3 item 6).
    public func transportConnected() async {
      guard state == .offer else {
        await fail(.protocolFailure)
        return
      }
      do {
        switch role {
        case .requester:
          try await beginRequesterCpace(now: clock.monotonicMilliseconds())

        case .proxy:
          guard preAuthentication.admit(nowMonotonicMs: clock.monotonicMilliseconds()) else {
            await transport.close()
            continuation.yield(.offerRestored)
            return
          }
          try bridge.beginCpace(
            candidateId: candidateID,
            randomBytes64: try entropy.cpaceRandom(),
            nowMonotonicMs: clock.monotonicMilliseconds())
          state = .custodianAwaitingStepOne
          if servesOfferAsFrame {
            try await transport.send(try bridge.encodedOffer())
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
      case .requesterAwaitingStepTwo:
        try bridge.readCpaceFrame(bytes: frame, nowMonotonicMs: now)
        continuation.yield(.keyConfirmed)
        let stepThree = try bridge.writeCpaceFrame(nowMonotonicMs: now)
        let handshakeOne = try bridge.writeHandshakeFrame(nowMonotonicMs: now)
        state = .requesterAwaitingHandshakeTwo
        armDeadline(after: Window.handshakeMilliseconds)
        try await transport.send(stepThree)
        try await transport.send(handshakeOne)

      case .requesterAwaitingHandshakeTwo:
        try bridge.readHandshakeFrame(bytes: frame, nowMonotonicMs: now)
        let handshakeThree = try bridge.writeHandshakeFrame(nowMonotonicMs: now)
        try enterPairingChannel(now: now)
        let hello = try bridge.sendHello(
          displayName: displayName, platform: platform, nowMonotonicMs: now)
        state = .awaitingPeerHello
        try await transport.send(handshakeThree)
        try await transport.send(hello)

      case .custodianAwaitingStepOne, .custodianAwaitingStepThree,
        .custodianAwaitingHandshakeOne, .custodianAwaitingHandshakeThree:
        try await receiveCustodianFrame(frame, now: now)

      case .awaitingPeerHello:
        try await receivePeerHello(frame, now: now)

      case .awaitingPeerConfirmation:
        try await receivePeerConfirmation(frame, now: now)

      case .awaitingPeerStored:
        try bridge.receiveStored(bytes: frame, nowMonotonicMs: now)
        try await activate(now: now)

      case .offer, .completed, .closed:
        await fail(.protocolFailure)
      }
    }

    /// The custodian's side of CPace and the pairing handshake.
    private func receiveCustodianFrame(_ frame: Data, now: UInt64) async throws {
      switch state {
      case .custodianAwaitingStepOne:
        try bridge.readCpaceFrame(bytes: frame, nowMonotonicMs: now)
        let stepTwo = try bridge.writeCpaceFrame(nowMonotonicMs: now)
        state = .custodianAwaitingStepThree
        armDeadline(after: Window.attemptMilliseconds)
        try await transport.send(stepTwo)

      case .custodianAwaitingStepThree:
        try bridge.readCpaceFrame(bytes: frame, nowMonotonicMs: now)
        state = .custodianAwaitingHandshakeOne
        armDeadline(after: Window.handshakeMilliseconds)

      case .custodianAwaitingHandshakeOne:
        try bridge.readHandshakeFrame(bytes: frame, nowMonotonicMs: now)
        let handshakeTwo = try bridge.writeHandshakeFrame(nowMonotonicMs: now)
        state = .custodianAwaitingHandshakeThree
        try await transport.send(handshakeTwo)

      case .custodianAwaitingHandshakeThree:
        try bridge.readHandshakeFrame(bytes: frame, nowMonotonicMs: now)
        try enterPairingChannel(now: now)
        state = .awaitingPeerHello

      default:
        await fail(.protocolFailure)
      }
    }

    /// The requester's first CPace message; step 2 is due within the
    /// attempt deadline (RAPP v26.10.29 §3.3 item 3).
    private func beginRequesterCpace(now: UInt64) async throws {
      try bridge.beginCpace(
        candidateId: candidateID, randomBytes64: try entropy.cpaceRandom(), nowMonotonicMs: now)
      let stepOne = try bridge.writeCpaceFrame(nowMonotonicMs: now)
      state = .requesterAwaitingStepTwo
      armDeadline(after: Window.attemptMilliseconds)
      try await transport.send(stepOne)
    }

    private func enterPairingChannel(now: UInt64) throws {
      guard try bridge.handshakeComplete(nowMonotonicMs: now) else {
        throw RappBindingError.ProtocolFailure
      }
      try bridge.enterConfirmation(nowMonotonicMs: now)
      armDeadline(after: Window.confirmationMilliseconds)
    }

    /// The requester introduces itself first; the custodian answers with its
    /// own introduction and the grant.
    private func receivePeerHello(_ frame: Data, now: UInt64) async throws {
      let peer = Peer(try bridge.receiveHello(bytes: frame, nowMonotonicMs: now))
      continuation.yield(.peerIntroduced(peer))
      switch role {
      case .requester:
        state = .awaitingPeerConfirmation

      case .proxy:
        let hello = try bridge.sendHello(
          displayName: displayName, platform: platform, nowMonotonicMs: now)
        let granted = profiles.filter { (peer.requestedProfiles ?? []).contains($0) }
        let grant = try bridge.sendConfirmation(grantedProfiles: granted, nowMonotonicMs: now)
        state = .awaitingPeerConfirmation
        try await transport.send(hello)
        try await transport.send(grant)
      }
    }

    /// Completes the grant exchange, stores the pairing and confirms the
    /// storage to the peer.
    ///
    /// The requester echoes the custodian's grant; the custodian accepts the
    /// echo. Either way both sets are now equal.
    private func receivePeerConfirmation(_ frame: Data, now: UInt64) async throws {
      let granted = try bridge.receiveConfirmation(bytes: frame, nowMonotonicMs: now)
      if role == .requester {
        let echo = try bridge.sendConfirmation(grantedProfiles: granted, nowMonotonicMs: now)
        try await transport.send(echo)
      }
      try await store(now: now)
    }

    // MARK: Store / Activate / Fail

    /// Stores the unconfirmed record, then tells the peer.
    ///
    /// The storage exchange is RAPP v26.10.29 §4.3 item 4; the
    /// confirmation deadline keeps running.
    private func store(now: UInt64) async throws {
      let record = try bridge.buildPairRecord(
        createdAtMs: clock.wallMilliseconds(), nowMonotonicMs: now)
      do {
        try record.persistDeviceOnly(vault: vault)
      } catch {
        await fail(.persistenceFailure)
        return
      }
      storedPairID = record.metadata().pairId
      let stored = try bridge.sendStored(nowMonotonicMs: now)
      state = .awaitingPeerStored
      try await transport.send(stored)
      try await activate(now: now)
    }

    /// Completes the pairing once both storage confirmations have been
    /// exchanged, storing the confirmed record over the unconfirmed one.
    private func activate(now: UInt64) async throws {
      guard let confirmed = try bridge.activatePairing(nowMonotonicMs: now) else { return }
      do {
        try confirmed.replaceDeviceOnly(vault: vault)
      } catch {
        await fail(.persistenceFailure)
        return
      }
      storedPairID = nil
      state = .completed
      cancelDeadline()
      continuation.yield(.paired(PairSummary(confirmed.metadata())))
      continuation.finish()
      await transport.close()
    }

    /// Revokes the record stored before the peer confirmed it, leaving
    /// its tombstone and what announces the revocation (§4.3 item 4, §4.6).
    private func revokeUnconfirmedRecord() {
      guard let pairID = storedPairID else { return }
      storedPairID = nil
      try? RappPairRevocation.revoke(pairID: pairID, in: vault, clock: clock)
    }

    private func handle(_ error: any Error) async {
      switch error {
      case RappBindingError.OfferExpired:
        await fail(.offerExpired)

      case RappBindingError.StorageUnconfirmed:
        await fail(.storageUnconfirmed)

      default:
        await abandonCandidate(.protocolFailure)
      }
    }

    /// Ends the connected attempt; a custodian keeps its offer while it
    /// lives and waits for the next connection (RAPP v26.10.29 §3.3 item 4).
    private func abandonCandidate(_ reason: CloseReason) async {
      guard state != .completed, state != .closed else { return }
      // A record stored for this attempt is not the next attempt's.
      revokeUnconfirmedRecord()
      if bridge.candidateFailed(nowMonotonicMs: clock.monotonicMilliseconds()) {
        state = .offer
        await transport.close()
        armDeadline(at: offerDeadlineMilliseconds)
        continuation.yield(.offerRestored)
        return
      }
      await fail(reason)
    }

    internal func fail(_ reason: CloseReason) async {
      guard state != .closed, state != .completed else { return }
      state = .closed
      cancelDeadline()
      bridge.cancelPairing()
      revokeUnconfirmedRecord()
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

      case .awaitingPeerStored:
        await fail(.storageUnconfirmed)

      case .requesterAwaitingStepTwo:
        await abandonCandidate(.attemptTimedOut)

      default:
        await abandonCandidate(.offerExpired)
      }
    }
  }
#endif
