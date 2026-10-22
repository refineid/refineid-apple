// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  extension RappPairingSearch {
    /// Opens the next endpoint found, when no pairing connection is open.
    internal func openNext() {
      guard !isEnded, attempt == nil,
        let endpoint = try? candidates.nextEndpoint()
      else { return }
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

    /// Handles one input of the connection open now; a closed connection's
    /// inputs are dropped.
    private func handle(_ step: Step, generation stepGeneration: Int) async {
      guard let current = attempt, current.generation == stepGeneration, !current.closing
      else { return }
      switch step {
      case .connection(.connected):
        attempt?.arrived = true
        guard current.coordinator == nil else { return }
        attempt?.feeders.append(offerDeadline(current.steps))

      case .connection(.frame(let frame)):
        if let coordinator = current.coordinator {
          await coordinator.receive(frame)
        } else {
          await admitOffer(frame, generation: stepGeneration)
        }

      case .connection(.closed):
        if let coordinator = current.coordinator {
          await coordinator.transportClosed()
        } else {
          await connectionEnded(.noOffer, generation: stepGeneration)
        }

      case .offerOverdue:
        guard current.coordinator == nil else { return }
        await connectionEnded(.noOffer, generation: stepGeneration)

      case .ceremony(let event):
        await ceremony(event, generation: stepGeneration)
      }
    }

    /// Reads the offer the connection served, admits it to the tries of
    /// the code and starts CPace on it.
    ///
    /// An offer the requester rejects, or one already tried with this code,
    /// closes the connection before CPace step 1 and spends no attempt.
    private func admitOffer(_ frame: Data, generation stepGeneration: Int) async {
      let bridge: RappPairingBridge
      let admitted: Bool
      do {
        bridge = try RappPairingBridge.bootstrapOffer(
          encodedOffer: frame, transportProfile: options.transportProfile, pairingCode: code,
          startedAtMonotonicMs: options.clock.monotonicMilliseconds())
        admitted = try candidates.beginTry(bridge)
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
      guard let current = attempt, current.generation == stepGeneration, !current.closing
      else { return }
      attempt?.closing = true
      stop(current)
      await current.coordinator?.close()
      await current.transport.close()
      guard !isEnded, attempt?.generation == stepGeneration else { return }
      attempt = nil
      // Only a connection whose custodian has not taken the code gets here,
      // so the ledger has a connection open and is not settled.
      guard let next = try? candidates.closed() else {
        await end(.ceremonyEnded(.protocolFailure))
        return
      }
      continuation.yield(.declined(refusal))
      switch next {
      case .tryNext:
        openNext()

      case .notAccepted:
        await end(.notAccepted)

      case .noneTried:
        if discoveryEnded {
          await end(.noneInPairingMode)
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
