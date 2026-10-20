// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG

  import CardCore
  import Foundation
  import os
  import RappEngine

  /// Drives both halves of a pairing over `fi.refineid.rapp.ble.v1`
  /// (RAPP v26.10.9 §4.2, §5) from the command line, and serves sessions
  /// over it with the stored pairings.
  ///
  /// The custodian prints the code it shows and serves its offer on the
  /// bootstrap characteristic; the requester takes the code from the
  /// environment, reads the offer, and runs the ceremony over GATT writes
  /// and indications. It grants exactly what typing the code grants. DEBUG
  /// only; the product does not offer this transport.
  internal enum DebugBlePairing {
    /// One link event or coordinator outcome, in arrival order.
    private enum Step: Sendable {
      case link(RappBleGattEvent)
      case pairing(RappPairingCoordinator.Event)
      case timeout
    }

    #if os(iOS) && REFINEID_LOCAL_CARD
      /// The routing state a peripheral's admission reads on its own queue.
      private struct SessionRouting: Sendable {
        var records: [RappPairRecord] = []
        let router = RappSessionRouter()
        var matched: RappPairRecord?
      }
    #endif

    /// What a script looks for on the line carrying the code.
    internal static let offerPrefix = "ble-offer-remote-reader: offer "

    /// How long either half waits: the offer's lifetime and a margin.
    private static let waitSeconds: UInt64 = 90
    /// The development proximity threshold §4.4 allows in isolation, in dBm.
    private static let developmentMinimumRssi = -85
    private static let custodianPrefix = "ble-offer-remote-reader"
    private static let requesterPrefix = "ble-pair-with-offer"
    private static let servePrefix = "ble-serve-remote-reader"

    /// The custodian half: show a code, serve the offer, wait.
    @MainActor
    internal static func offer() async -> DebugModeReport {
      let code = RappPairingCode.generate()
      let (steps, sink) = AsyncStream.makeStream(of: Step.self)
      let box = DebugLinkBox<RappBleGattPeripheral>()
      let transport = RappClosureFrameTransport(
        sender: { frame in
          guard let link = box.value else { throw RappBleGattFailure.disconnected }
          try await link.send(frame)
        },
        closer: { box.value?.cancel() })
      let coordinator: RappPairingCoordinator
      let offer: Data
      do {
        coordinator = try RappPairingCoordinator.custodian(
          options: options(code: code, transport: transport))
        offer = try await coordinator.bootstrapOffer()
      } catch {
        return DebugModeReport(
          lines: [custodianPrefix + ": the offer could not be made"], succeeded: false)
      }
      let link = RappBleGattPeripheral(
        bootstrapOffer: offer, admits: { purpose in purpose == .pairing },
        onEvent: { event in sink.yield(.link(event)) })
      box.value = link
      defer { link.cancel() }
      DebugConsole.emit(offerPrefix + code)
      return await drive(
        coordinator: coordinator, steps: steps, sink: sink, prefix: custodianPrefix
      ) {
        await coordinator.start()
        link.start()
      }
    }

    /// The requester half: find the custodian, read its offer, pair.
    @MainActor
    internal static func pair(code raw: String) async -> DebugModeReport {
      let code = RappPairingCode.normalize(raw.trimmingCharacters(in: .whitespacesAndNewlines))
      guard RappPairingCode.isValid(code) else {
        return DebugModeReport(
          lines: [requesterPrefix + ": the argument is not a pairing code"], succeeded: false)
      }
      let (steps, sink) = AsyncStream.makeStream(of: Step.self)
      let link = RappBleGattCentral(
        purpose: .pairing, minimumRssi: developmentMinimumRssi,
        onEvent: { event in sink.yield(.link(event)) })
      defer { link.cancel() }
      let transport = RappClosureFrameTransport(
        sender: { frame in try await link.send(frame) }, closer: { link.cancel() })
      link.start()
      let timeout = Task {
        try? await Task.sleep(for: .seconds(waitSeconds))
        sink.yield(.timeout)
      }
      defer { timeout.cancel() }
      for await step in steps {
        guard case .link(let event) = step else {
          if case .timeout = step {
            return DebugModeReport(
              lines: [requesterPrefix + ": no custodian was found"], succeeded: false)
          }
          continue
        }
        switch event {
        case .bootstrapOffer(let offer):
          guard
            let coordinator = try? RappPairingCoordinator.requester(
              options: options(code: code, transport: transport), bootstrapOffer: offer)
          else {
            return DebugModeReport(
              lines: [requesterPrefix + ": the custodian's offer was refused"], succeeded: false)
          }
          DebugConsole.emit(requesterPrefix + ": read the bootstrap offer")
          return await drive(
            coordinator: coordinator, steps: steps, sink: sink, prefix: requesterPrefix
          ) { await coordinator.start() }

        case .closed(let failure):
          return DebugModeReport(
            lines: [requesterPrefix + ": link closed before the offer: \(failure)"],
            succeeded: false)

        case .connected, .frame:
          continue
        }
      }
      return DebugModeReport(lines: [requesterPrefix + ": ended"], succeeded: false)
    }

    #if os(iOS) && REFINEID_LOCAL_CARD
      /// The custodian serving sessions: admit a session preamble naming a
      /// stored pairing, run the session through the relay, and advertise
      /// again after each close, until the process is stopped.
      @MainActor
      internal static func serve() async -> DebugModeReport {
        let relay = PhonePersistentTokenRelay.shared
        let routing = OSAllocatedUnfairLock(initialState: SessionRouting())
        while true {
          let records = PhoneStreamPairContext.resolveAll(vault: relay.vault).map(\.pairRecord)
          guard !records.isEmpty else {
            return DebugModeReport(
              lines: [servePrefix + ": no pairing is stored"], succeeded: false)
          }
          routing.withLock { state in
            state.records = records
            state.matched = nil
          }
          let (events, sink) = AsyncStream.makeStream(of: RappBleGattEvent.self)
          let link = RappBleGattPeripheral(
            bootstrapOffer: nil,
            admits: { purpose in
              guard case .session(let preamble) = purpose else { return false }
              return routing.withLock { state in
                let route = state.router.route(
                  transportProfile: RappBleGattProfile.name, preamble: preamble,
                  records: state.records)
                guard case .session(let index) = route, state.records.indices.contains(index)
                else { return false }
                state.matched = state.records[index]
                return true
              }
            },
            onEvent: { event in sink.yield(event) })
          DebugConsole.emit(servePrefix + ": advertising")
          link.start()
          await serveConnection(
            link: link, events: events, matched: { routing.withLock { $0.matched } })
          link.cancel()
        }
      }

      /// Runs one admitted connection through the relay until its link closes.
      @MainActor
      private static func serveConnection(
        link: RappBleGattPeripheral,
        events: AsyncStream<RappBleGattEvent>,
        matched: () -> RappPairRecord?
      ) async {
        let relay = PhonePersistentTokenRelay.shared
        var connection: UUID?
        for await event in events {
          switch event {
          case .connected:
            let transport = RappClosureFrameTransport(
              sender: { frame in try await link.send(frame) }, closer: { link.cancel() })
            if let pair = matched() {
              connection = relay.serveRoutedSession(
                pair: pair, transportProfile: RappBleGattProfile.name, transport: transport
              ) { link.cancel() }
            }
            if connection == nil {
              DebugConsole.emit(servePrefix + ": refused, another session is open")
              link.cancel()
            } else {
              DebugConsole.emit(servePrefix + ": session routed")
            }

          case .frame(let frame):
            if let connection {
              relay.receiveRoutedFrame(frame, connectionID: connection) { link.cancel() }
            }

          case .closed(let failure):
            DebugConsole.emit(servePrefix + ": link closed: \(failure)")
            if let connection {
              relay.routedSessionClosed(connectionID: connection)
            }
            return

          case .bootstrapOffer:
            continue
          }
        }
      }
    #endif

    @MainActor
    private static func options(
      code: String, transport: any RappFrameTransport
    ) -> RappPairingCoordinator.Options {
      RappPairingCoordinator.Options(
        code: code,
        profiles: RappApplePeerProfile.supportedCredentialProfiles,
        transportProfile: RappBleGattProfile.name,
        displayName: RappPairingModel.localDisplayName,
        platform: RappPairingModel.localPlatform,
        vault: RappDeviceVault(),
        transport: transport)
    }

    /// Feeds link events to the coordinator in order until it reports a
    /// pairing or a close.
    @MainActor
    private static func drive(
      coordinator: RappPairingCoordinator,
      steps: AsyncStream<Step>,
      sink: AsyncStream<Step>.Continuation,
      prefix: String,
      start: () async -> Void
    ) async -> DebugModeReport {
      let events = Task {
        for await event in coordinator.events {
          sink.yield(.pairing(event))
        }
      }
      let timeout = Task {
        try? await Task.sleep(for: .seconds(waitSeconds))
        sink.yield(.timeout)
      }
      defer {
        events.cancel()
        timeout.cancel()
      }
      await start()
      for await step in steps {
        switch step {
        case .link(.connected):
          DebugConsole.emit(prefix + ": routed")
          await coordinator.transportConnected()

        case .link(.frame(let frame)):
          await coordinator.receive(frame)

        case .link(.closed(let failure)):
          DebugConsole.emit(prefix + ": link closed: \(failure)")
          await coordinator.transportClosed()

        case .pairing(.paired(let summary)):
          return DebugModeReport(
            lines: [prefix + ": paired over " + summary.transportProfile], succeeded: true)

        case .pairing(.closed(let reason)):
          return DebugModeReport(lines: [prefix + ": ceremony ended: \(reason)"], succeeded: false)

        case .timeout:
          await coordinator.close()
          return DebugModeReport(lines: [prefix + ": timed out"], succeeded: false)

        case .link(.bootstrapOffer), .pairing:
          continue
        }
      }
      return DebugModeReport(lines: [prefix + ": ended"], succeeded: false)
    }
  }

#endif
