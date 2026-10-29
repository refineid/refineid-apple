// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  extension RappPairingSearch {
    /// Opens the next endpoint found, when no pairing connection is open.
    internal func openNext() async {
      guard !isEnded, attempt == nil else { return }
      guard remoteUseAvailable() else {
        await end(.interrupted)
        return
      }
      let now = options.clock.monotonicMilliseconds()
      let endpoint: Endpoint
      switch try? candidates.nextEndpoint(nowMonotonicMs: now) {
      case .open(let next):
        endpoint = next

      case .notBefore(let monotonicMs):
        reopen(at: monotonicMs, now: now)
        return

      case .exhausted, nil:
        return
      }
      reopening?.cancel()
      reopening = nil
      generation += 1
      let current = generation
      let connection = dial(endpoint)
      let (steps, sink) = AsyncStream.makeStream(of: Step.self)
      let reader = Task {
        for await event in connection.events {
          sink.yield(.connection(event))
        }
      }
      var opened = Attempt(generation: current, transport: connection.transport, steps: sink)
      opened.feeders.append(reader)
      attempt = opened
      Task { [weak self] in
        for await step in steps {
          await self?.handle(step, generation: current)
        }
      }
    }

    /// Opens the next endpoint once the earliest busy custodian's wait has
    /// passed, showing nothing meanwhile.
    private func reopen(at monotonicMs: UInt64, now: UInt64) {
      reopening?.cancel()
      let delay = monotonicMs > now ? monotonicMs - now : 0
      reopening = Task { [weak self] in
        do {
          try await Task.sleep(for: .milliseconds(delay))
        } catch {
          return
        }
        await self?.reopenDue()
      }
    }

    private func reopenDue() async {
      reopening = nil
      await openNext()
    }

    /// Handles one input of the connection open now; a closed connection's
    /// inputs are dropped.
    private func handle(_ step: Step, generation stepGeneration: Int) async {
      guard let current = attempt, current.generation == stepGeneration, !current.closing
      else { return }
      switch step {
      case .connection(let event):
        await connection(event, of: current)

      case .offerOverdue:
        guard current.coordinator == nil else { return }
        await connectionEnded(.noOffer, generation: stepGeneration)

      case .ceremony(let event):
        await ceremony(event, generation: stepGeneration)
      }
    }

    /// What the connection open now reports.
    private func connection(_ event: RappPairingConnection.Event, of current: Attempt) async {
      switch event {
      case .connected:
        attempt?.arrived = true
        anyOpened = true
        guard current.coordinator == nil else { return }
        attempt?.feeders.append(offerDeadline(current.steps))

      case .frame(let frame):
        if let coordinator = current.coordinator {
          await coordinator.receive(frame)
        } else {
          await admitOffer(frame, generation: current.generation)
        }

      case .closed:
        if let coordinator = current.coordinator {
          await coordinator.transportClosed()
        } else {
          await connectionEnded(.noOffer, generation: current.generation)
        }

      case .notOpened(let failure):
        await connectionEnded(.notOpened(failure), generation: current.generation)
      }
    }

    /// Reads the bootstrap answer the connection served, admits its offer
    /// to the tries of the code and starts CPace on it.
    ///
    /// An offer the requester rejects, or one already tried with this code,
    /// closes the connection before CPace step 1 and spends no attempt. A
    /// `pairing-busy` defers the endpoint.
    private func admitOffer(_ frame: Data, generation stepGeneration: Int) async {
      let bridge: RappPairingBridge
      let admitted: Bool
      do {
        bridge = try RappPairingBridge.bootstrapOffer(
          bootstrap: frame, transportProfile: options.transportProfile, pairingCode: code,
          startedAtMonotonicMs: options.clock.monotonicMilliseconds())
        admitted = try candidates.beginTry(bridge)
      } catch RappBindingError.CustodianBusy {
        guard let retryAfter = try? rappPairingBusyRetryAfterMs(frame) else {
          await connectionEnded(.offerRejected, generation: stepGeneration)
          return
        }
        await custodianBusy(retryAfterMilliseconds: retryAfter, generation: stepGeneration)
        return
      } catch {
        await connectionEnded(.offerRejected, generation: stepGeneration)
        return
      }
      guard admitted else {
        await connectionEnded(.offerAlreadyTried, generation: stepGeneration)
        return
      }
      guard let current = attempt else { return }
      let coordinator: RappPairingCoordinator
      do {
        coordinator = try RappPairingCoordinator.requester(
          options: options, transport: current.transport, bootstrap: bridge)
      } catch {
        await connectionEnded(.offerRejected, generation: stepGeneration)
        return
      }
      let sink = current.steps
      let forwarder = Task {
        for await event in coordinator.events {
          sink.yield(.ceremony(event))
        }
      }
      attempt?.coordinator = coordinator
      attempt?.feeders.append(forwarder)
      await coordinator.start()
      await coordinator.transportConnected()
    }

    /// What the ceremony on the open connection reports.
    private func ceremony(
      _ event: RappPairingCoordinator.Event, generation stepGeneration: Int
    ) async {
      switch event {
      case .keyConfirmed:
        // The custodian holds the code: no other custodian is tried with it.
        codeAccepted = (try? candidates.accepted()) != nil

      case .peerIntroduced(let peer):
        continuation.yield(.peerIntroduced(peer))

      case .paired(let summary):
        finishPaired(summary)

      case .closed(.custodianBusy(let retryAfter)) where !codeAccepted:
        await custodianBusy(retryAfterMilliseconds: retryAfter, generation: stepGeneration)

      case .closed(let reason):
        if codeAccepted {
          await end(.ceremonyEnded(reason))
        } else {
          await connectionEnded(.refused(reason), generation: stepGeneration)
        }

      case .offerRestored:
        break
      }
    }

    /// Closes the open connection, whose custodian did not take the code,
    /// and tries the next endpoint or reports the search's outcome.
    ///
    /// The connection is closed before the next one opens (§4.2 item 3).
    internal func connectionEnded(_ refusal: Refusal, generation stepGeneration: Int) async {
      guard await closeOpenConnection(generation: stepGeneration) else { return }
      if case .notOpened(let failure) = refusal {
        openFailures.insert(failure)
      }
      // Only a connection whose custodian has not taken the code gets here,
      // so the ledger has a connection open and is not settled.
      guard let next = try? candidates.closed(remoteUseAvailable: remoteUseAvailable()) else {
        await end(.ceremonyEnded(.protocolFailure))
        return
      }
      continuation.yield(.declined(refusal))
      await proceed(after: next)
    }

    /// Closes the open connection, whose custodian answered `pairing-busy`.
    ///
    /// The endpoint is kept for another opening no sooner than
    /// `retryAfterMilliseconds` (§4.2, "Busy Refusal"). A busy answer is not
    /// a refusal, and nothing is shown.
    internal func custodianBusy(
      retryAfterMilliseconds: UInt64, generation stepGeneration: Int
    ) async {
      guard await closeOpenConnection(generation: stepGeneration) else { return }
      guard
        let next = try? candidates.busy(
          retryAfterMs: retryAfterMilliseconds,
          nowMonotonicMs: options.clock.monotonicMilliseconds(),
          remoteUseAvailable: remoteUseAvailable())
      else {
        await end(.ceremonyEnded(.protocolFailure))
        return
      }
      await proceed(after: next)
    }

    /// Closes the connection of `stepGeneration` while it is the one open;
    /// false when it is not, or the search ended meanwhile.
    private func closeOpenConnection(generation stepGeneration: Int) async -> Bool {
      guard let current = attempt, current.generation == stepGeneration, !current.closing
      else { return false }
      attempt?.closing = true
      stop(current)
      await current.coordinator?.close()
      await current.transport.close()
      guard !isEnded, attempt?.generation == stepGeneration else { return false }
      attempt = nil
      return true
    }

    /// Tries the next endpoint or reports the search's outcome.
    private func proceed(after next: RappNextCandidate) async {
      switch next {
      case .interrupted:
        await end(.interrupted)

      case .tryNext, .deferred:
        await openNext()

      case .notAccepted:
        await end(.notAccepted)

      case .noneTried:
        if discoveryEnded || localNetworkDenied {
          await end(noneTriedReason)
        }
      }
    }

    /// Reports the offer overdue once an open connection has had its time
    /// to serve it.
    private func offerDeadline(_ sink: AsyncStream<Step>.Continuation) -> Task<Void, Never> {
      Task {
        do {
          try await Task.sleep(for: .milliseconds(RappPairingConnection.offerReadMilliseconds))
        } catch {
          return
        }
        sink.yield(.offerOverdue)
      }
    }
  }
#endif
