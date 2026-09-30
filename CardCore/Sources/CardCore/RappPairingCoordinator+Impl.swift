// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  extension RappPairingCoordinator {
    // MARK: Public API

    /// Publishes the requester QR without consuming it or starting transport.
    public func publishOffer() {
      guard state == .offer, let offerURI else { return }
      continuation.yield(.offerReady(uri: offerURI))
      scheduleOfferExpiry()
    }

    /// Installs the transport for the next candidate after the requester
    /// retained its still-live offer.
    ///
    /// Replacement is legal only while the coordinator projects `offer_active`.
    @discardableResult
    public func replaceTransport(_ replacement: any RappFrameTransport) -> Bool {
      guard state == .offer else { return false }
      transport = replacement
      return true
    }

    /// Consumes the offer only after the selected candidate is connected.
    public func transportConnected() async {
      guard state == .offer else {
        await fail(.protocolFailure)
        return
      }
      scheduleOfferExpiry()
      do {
        let randomBytes = try RappPlatformEntropy().cpaceRandom()
        try bridge.beginCpace(
          candidateId: candidateID,
          pairingCode: pairingCode,
          randomBytes64: randomBytes,
          nowMonotonicMs: clock.monotonicMilliseconds()
        )
        switch role {
        case .requester:
          let frame = try bridge.writeCpaceFrame(nowMonotonicMs: clock.monotonicMilliseconds())
          state = .awaitingResponderCpace
          try await transport.send(frame)
        case .proxy:
          state = .awaitingRequesterCpace
        }
      } catch RappBindingError.OfferExpired {
        await fail(.offerExpired)
      } catch {
        await recoverOrFail(.transportFailure, closeCandidate: true)
      }
    }

    /// Consumes one complete opaque frame received from the transport.
    public func receive(_ frame: Data) async {
      do {
        try await receiveFrame(frame)
      } catch RappBindingError.OfferExpired {
        print("[pairing-coordinator] receive OfferExpired")
        Darwin.fflush(stdout)
        await fail(.offerExpired)
      } catch {
        print("[pairing-coordinator] receive failed: \(error)")
        Darwin.fflush(stdout)
        await recoverOrFail(.protocolFailure, closeCandidate: true)
      }
    }

    /// Sends the exact user-approved grant set.
    ///
    /// Pair persistence remains impossible until the authenticated peer grant
    /// has also arrived.
    public func approve(grantedProfiles: [String]) async {
      guard state == .awaitingLocalDecision, peer != nil else {
        print(
          "[pairing-coordinator] approve failed: state=\(state)"
            + " peer=\(String(describing: peer))"
        )
        Darwin.fflush(stdout)
        await fail(.protocolFailure)
        return
      }
      do {
        let frame = try bridge.sendConfirmation(grantedProfiles: grantedProfiles)
        try await transport.send(frame)
        localConfirmationSent = true
        if peerGrantedProfiles.isEmpty {
          state = .awaitingPeerConfirmation
        } else {
          try await finishIfMutuallyConfirmed()
        }
      } catch {
        print("[pairing-coordinator] approve failed: \(error)")
        Darwin.fflush(stdout)
        await fail(.protocolFailure)
      }
    }

    /// Denies the reviewed peer and ends the attempt without a pair.
    public func deny() async {
      guard state == .awaitingLocalDecision else { return }
      await fail(.denied)
    }

    /// Reacts to transport closure, restoring the requester offer when legal.
    public func transportClosed() async {
      switch state {
      case .offer:
        return
      case .awaitingRequesterCpace,
        .awaitingResponderCpace,
        .awaitingRequesterHandshake,
        .awaitingResponderHandshake,
        .awaitingFinalRequesterHandshake:
        await recoverOrFail(.transportFailure, closeCandidate: false)
      case .awaitingPeerHello,
        .awaitingLocalDecision,
        .awaitingPeerConfirmation,
        .completed,
        .closed:
        await fail(.transportFailure)
      }
    }

    /// Ends the pairing attempt at local request.
    public func close() async {
      await fail(.localRequest)
    }

    // MARK: Frame Dispatch

    /// Routes an inbound frame to the appropriate per-state handler.
    internal func receiveFrame(_ frame: Data) async throws {
      switch state {
      case .awaitingRequesterCpace:
        try await receiveRequesterCpace(frame)
      case .awaitingResponderCpace:
        try await receiveResponderCpace(frame)
      case .awaitingRequesterHandshake:
        try await receiveRequesterHandshake(frame)
      case .awaitingResponderHandshake:
        try await receiveResponderHandshake(frame)
      case .awaitingFinalRequesterHandshake:
        try await receiveFinalRequesterHandshake(frame)
      case .awaitingPeerHello:
        try receivePeerHello(frame)
      case .awaitingLocalDecision:
        peerGrantedProfiles = try bridge.receiveConfirmation(
          bytes: frame, nowMs: clock.wallMilliseconds()
        )
      case .awaitingPeerConfirmation:
        peerGrantedProfiles = try bridge.receiveConfirmation(
          bytes: frame, nowMs: clock.wallMilliseconds()
        )
        try await finishIfMutuallyConfirmed()
      case .offer, .completed, .closed:
        await fail(.protocolFailure)
      }
    }

    // MARK: Handshake Handlers

    private func receiveRequesterCpace(_ frame: Data) async throws {
      let response = try bridge.writeCpaceFrame(nowMonotonicMs: clock.monotonicMilliseconds())
      try bridge.readCpaceFrame(bytes: frame, nowMonotonicMs: clock.monotonicMilliseconds())
      state = .awaitingRequesterHandshake
      try await transport.send(response)
    }

    private func receiveResponderCpace(_ frame: Data) async throws {
      try bridge.readCpaceFrame(bytes: frame, nowMonotonicMs: clock.monotonicMilliseconds())
      let handshakeFrame = try bridge.writeHandshakeFrame(
        nowMonotonicMs: clock.monotonicMilliseconds()
      )
      state = .awaitingResponderHandshake
      try await transport.send(handshakeFrame)
    }

    private func receiveRequesterHandshake(_ frame: Data) async throws {
      try bridge.readHandshakeFrame(bytes: frame, nowMonotonicMs: clock.monotonicMilliseconds())
      let response = try bridge.writeHandshakeFrame(nowMonotonicMs: clock.monotonicMilliseconds())
      state = .awaitingFinalRequesterHandshake
      try await transport.send(response)
    }

    private func receiveResponderHandshake(_ frame: Data) async throws {
      try bridge.readHandshakeFrame(bytes: frame, nowMonotonicMs: clock.monotonicMilliseconds())
      let finalHandshake = try bridge.writeHandshakeFrame(
        nowMonotonicMs: clock.monotonicMilliseconds()
      )
      guard try bridge.handshakeComplete(nowMonotonicMs: clock.monotonicMilliseconds()) else {
        await recoverOrFail(.protocolFailure, closeCandidate: true)
        return
      }
      try bridge.enterConfirmation(nowMonotonicMs: clock.monotonicMilliseconds())
      cancelOfferExpiry()
      let hello = try bridge.sendHello(displayName: displayName, platform: platform)
      state = .awaitingPeerHello
      try await transport.send(finalHandshake)
      try await transport.send(hello)
    }

    private func receiveFinalRequesterHandshake(_ frame: Data) async throws {
      try bridge.readHandshakeFrame(bytes: frame, nowMonotonicMs: clock.monotonicMilliseconds())
      guard try bridge.handshakeComplete(nowMonotonicMs: clock.monotonicMilliseconds()) else {
        await recoverOrFail(.protocolFailure, closeCandidate: true)
        return
      }
      try bridge.enterConfirmation(nowMonotonicMs: clock.monotonicMilliseconds())
      cancelOfferExpiry()
      let hello = try bridge.sendHello(displayName: displayName, platform: platform)
      state = .awaitingPeerHello
      try await transport.send(hello)
    }

    private func receivePeerHello(_ frame: Data) throws {
      let received = try bridge.receiveHello(bytes: frame, nowMs: clock.wallMilliseconds())
      let newPeer = Peer(received)
      self.peer = newPeer
      state = .awaitingLocalDecision
      continuation.yield(.reviewPeer(newPeer))
    }

    // MARK: Finish / Fail

    internal func finishIfMutuallyConfirmed() async throws {
      guard localConfirmationSent, !peerGrantedProfiles.isEmpty else {
        print(
          "[pairing-coordinator] finishIfMutuallyConfirmed waiting:"
            + " localSent=\(localConfirmationSent)"
            + " peerGrants=\(peerGrantedProfiles)"
        )
        Darwin.fflush(stdout)
        return
      }
      print("[pairing-coordinator] finishIfMutuallyConfirmed: executing finishPairing")
      Darwin.fflush(stdout)
      let record: RappPairRecord
      do {
        record = try bridge.finishPairing(createdAtMs: clock.wallMilliseconds())
      } catch {
        print("[pairing-coordinator] bridge.finishPairing failed: \(error)")
        Darwin.fflush(stdout)
        throw error
      }
      do {
        try record.persistDeviceOnly(vault: vault)
        let summary = PairSummary(record.metadata())
        state = .completed
        cancelOfferExpiry()
        continuation.yield(.paired(summary))
        continuation.finish()
        await transport.close()
      } catch {
        print("[pairing-coordinator] record.persistDeviceOnly failed: \(error)")
        Darwin.fflush(stdout)
        await fail(.persistenceFailure)
      }
    }

    internal func fail(_ reason: CloseReason) async {
      guard state != .closed, state != .completed else { return }
      state = .closed
      cancelOfferExpiry()
      bridge.cancelPairing()
      await transport.close()
      continuation.yield(.closed(reason))
      continuation.finish()
    }

    internal func recoverOrFail(_ terminalReason: CloseReason, closeCandidate: Bool) async {
      do {
        if try await restoreRequesterOffer(closeCandidate: closeCandidate) {
          return
        }
      } catch RappBindingError.OfferExpired {
        await fail(.offerExpired)
        return
      } catch {
        // A state that cannot expose the original live offer is terminal.
      }
      await fail(terminalReason)
    }

    // MARK: Offer Lifecycle

    private func restoreRequesterOffer(closeCandidate: Bool) async throws -> Bool {
      guard case .requester = role else { return false }
      let now = clock.monotonicMilliseconds()
      switch state {
      case .offer:
        break
      case .awaitingRequesterCpace,
        .awaitingResponderCpace,
        .awaitingRequesterHandshake,
        .awaitingResponderHandshake,
        .awaitingFinalRequesterHandshake:
        do {
          guard try bridge.candidateFailed(nowMonotonicMs: now) else { return false }
        } catch RappBindingError.WrongPhase {
          // Frame processing already restored the offer atomically.
        }
      case .awaitingPeerHello,
        .awaitingLocalDecision,
        .awaitingPeerConfirmation,
        .completed,
        .closed:
        return false
      }
      let uri = try bridge.offerUri(nowMonotonicMs: now)
      state = .offer
      if closeCandidate { await transport.close() }
      continuation.yield(.offerRestored(uri: uri))
      scheduleOfferExpiry()
      return true
    }

    internal func scheduleOfferExpiry() {
      guard offerExpiryTask == nil else { return }
      let now = clock.monotonicMilliseconds()
      enum Timing {
        static let nanosecondsPerMillisecond: UInt64 = 1_000_000
      }
      let maximumDelayNanoseconds = UInt64.max
      let remainingMilliseconds =
        offerDeadlineMilliseconds > now
        ? offerDeadlineMilliseconds - now
        : 0
      let (nanoseconds, overflow) = remainingMilliseconds.multipliedReportingOverflow(
        by: Timing.nanosecondsPerMillisecond
      )
      let delay = overflow ? maximumDelayNanoseconds : nanoseconds
      offerExpiryTask = Task { [weak self] in
        do { try await Task.sleep(nanoseconds: delay) } catch { return }
        guard !Task.isCancelled, let self else { return }
        await expireOffer()
      }
    }

    private func cancelOfferExpiry() {
      offerExpiryTask?.cancel()
      offerExpiryTask = nil
    }

    private func expireOffer() async {
      guard
        state == .offer
          || state == .awaitingRequesterCpace
          || state == .awaitingResponderCpace
          || state == .awaitingRequesterHandshake
          || state == .awaitingResponderHandshake
          || state == .awaitingFinalRequesterHandshake
      else { return }
      await fail(.offerExpired)
    }
  }
#endif
