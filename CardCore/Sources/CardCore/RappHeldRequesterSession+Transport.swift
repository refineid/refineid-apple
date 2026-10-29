// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(MultipeerConnectivity) && canImport(RappEngine) && REFINEID_STREAM_TRANSPORT
  import Foundation
  import Network
  import RappEngine

  /// How the held session reaches the custodian and runs its exchange: the
  /// stream dialer or the Bluetooth central below, the coordinator above.
  extension RappHeldRequesterSession {
    internal func startStream() {
      let followed = pair
      let found = StreamRelayBrowser(
        matchingRecord: { record in
          StreamRendezvousName.sessionRecord(record, holds: followed, at: Date())
        },
        onFound: { [weak self] endpoint in
          self?.dial(endpoint)
        })
      link.browse(with: found)
      found.start()
    }

    internal func startBluetooth(_ peers: RappBleCentralPeers) {
      guard
        let preamble = try? pair.sessionPreamble(transportProfile: RappBleGattProfile.name)
      else {
        finish(.transportFailure)
        return
      }
      let central = RappBleGattCentral(purpose: .session(preamble: preamble), peers: peers) {
        [weak self] event in
        self?.receive(event)
      }
      link.carry(over: central)
      central.start()
    }

    private func dial(_ endpoint: NWEndpoint) {
      guard
        let preamble = try? pair.sessionPreamble(transportProfile: rappStreamProfileName())
      else {
        finish(.transportFailure)
        return
      }
      let made = StreamRelaySession(service: endpoint, preamble: preamble) { [weak self] event in
        self?.receive(PersistentRelayEvent(event))
      }
      guard !state.withLock({ $0.finished }), link.dial(with: made) else { return }
      made.start()
    }

    private func receive(_ event: RappBleGattEvent) {
      switch event {
      case .peer(let peer):
        state.withLock { $0.bluetoothPeer = peer }

      case .connected:
        if let peer = state.withLock({ $0.bluetoothPeer }) {
          report(.bluetoothPeer(peer, routed: true))
        }
        receive(PersistentRelayEvent.connected)

      case .frame(let frame):
        receive(PersistentRelayEvent.frame(frame))

      case .closed(let failure):
        if failure == .routingRefused, let peer = state.withLock({ $0.bluetoothPeer }) {
          report(.bluetoothPeer(peer, routed: false))
        }
        receive(PersistentRelayEvent.closed(.disconnected))

      case .trace(let step):
        report(.bluetoothTrace(step))

      case .attemptRefused, .bootstrap:
        // A session link never reads the bootstrap characteristic.
        break
      }
    }

    private func receive(_ event: PersistentRelayEvent) {
      switch event {
      case .connected:
        state.withLock { $0.connected = true }
        deliverInOrder { [weak self] in
          await self?.establish()
        }

      case .frame(let frame):
        deliverInOrder { [weak self] in
          let coordinator = self?.state.withLock { $0.coordinator }
          await coordinator?.receive(frame)
        }

      case .closed(let failure):
        if case .localNetworkDenied = failure {
          report(.localNetworkDenied)
        }
        // The coordinator names the end: a close the custodian announced
        // keeps its reason, a bare transport loss is a failure.
        deliverInOrder { [weak self] in
          guard let self else { return }
          if let coordinator = state.withLock({ $0.coordinator }) {
            await coordinator.transportClosed()
          } else {
            finish(.transportFailure)
          }
        }
      }
    }

    private func deliverInOrder(_ work: @escaping @Sendable () async -> Void) {
      if frameDelivery.deliver(work) { return }
      finish(.transportFailure)
    }

    private func establish() async {
      do {
        let coordinator = try RappConnectionCoordinator(
          role: .requester,
          pair: pair,
          transport: transport,
          maximumLifetimeMilliseconds: policy.maximumOperationLifetimeMilliseconds,
          transportProfile: route.transportProfile
        )
        let installed = state.withLock { state -> Bool in
          guard state.coordinator == nil, !state.finished else { return false }
          state.coordinator = coordinator
          return true
        }
        guard installed else { return }
        Task { [weak self] in
          for await event in coordinator.events {
            await self?.receive(event, from: coordinator)
          }
        }
        await coordinator.start()
      } catch {
        finish(.handshake(.protocolFailure))
      }
    }

    private func receive(
      _ event: RappConnectionCoordinator.Event, from coordinator: RappConnectionCoordinator
    ) async {
      switch event {
      case .established:
        state.withLock { $0.established = true }
        Self.settleEstablishment(state, true)
        report(.established)

      case .cardStatus(let status):
        report(.cardStatus(status))

      case .progress(_, let progressEvent):
        RappRequesterNotices.post(progress: progressEvent)

      case .completed(_, let result):
        RappRequesterNotices.post(RappCardPromptNotificationNames.cardDismissDarwinNotification)
        Self.settle(state, .success(result))

      case .terminal(_, let reason):
        RappRequesterNotices.post(RappCardPromptNotificationNames.cardDismissDarwinNotification)
        Self.settle(state, .failure(OperationError.terminal(reason)))

      case .operationEnded:
        Self.settle(state, .failure(OperationError.closed))

      case .answered:
        // Only a custodian answers an operation.
        break

      case .closed(let reason):
        RappRequesterNotices.post(RappCardPromptNotificationNames.cardDismissDarwinNotification)
        finish(reason)

      case .inspectPrerequisites, .awaitUserApproval, .executeSafeRead, .executeCardCommand:
        await coordinator.close()
        finish(.operation(.protocolFailure))
      }
    }
  }
#endif
