// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG

  import CardCore
  import Foundation
  import RappEngine

  /// Drives both halves of a pairing over `fi.refineid.rapp.ble`
  /// (RAPP v26.10.29 §4.2, §5) from the command line.
  ///
  /// The custodian prints the code it shows and serves its offer on the
  /// bootstrap characteristic; the requester takes the code from the
  /// environment, reads the offer, and runs the ceremony over GATT writes
  /// and indications. It grants exactly what typing the code grants. DEBUG
  /// only; the product pairs over the stream and serves sessions over
  /// both transports.
  internal enum DebugBlePairing {
    /// What a link reports to the ceremony, on either side.
    private enum LinkStep: Sendable {
      case attemptRefused(Data)
      case bootstrap(Data)
      case closed(RappBleGattFailure)
      case connected
      case frame(Data)
      case trace(RappBleGattTrace)

      /// The requester's link event.
      init?(_ event: RappBleGattEvent) {
        switch event {
        case .attemptRefused(let answer):
          self = .attemptRefused(answer)

        case .bootstrap(let answer):
          self = .bootstrap(answer)

        case .closed(let failure):
          self = .closed(failure)

        case .connected:
          self = .connected

        case .frame(let frame):
          self = .frame(frame)

        case .trace(let step):
          self = .trace(step)

        case .peer:
          return nil
        }
      }

      /// The custodian's link event; the ceremony runs on one link.
      init(_ event: RappBleGattServerEvent) {
        switch event {
        case .routed:
          self = .connected

        case .frame(_, let frame):
          self = .frame(frame)

        case .closed(_, let failure):
          self = .closed(failure)

        case .trace(let step):
          self = .trace(step)
        }
      }
    }

    /// One link event or coordinator outcome, in arrival order.
    private enum Step: Sendable {
      case link(LinkStep)
      case pairing(RappPairingCoordinator.Event)
      case timeout
    }

    /// What a script looks for on the line carrying the code.
    internal static let offerPrefix = "ble-offer-remote-reader: offer "

    /// How long either half waits: the offer's lifetime and a margin.
    private static let waitSeconds: UInt64 = 90
    private static let custodianPrefix = "ble-offer-remote-reader"
    private static let requesterPrefix = "ble-pair-with-offer"

    /// The custodian half: show a code, serve the bootstrap answer, wait.
    @MainActor
    internal static func offer() async -> DebugModeReport {
      let code = RappPairingCode.generate()
      let (steps, sink) = AsyncStream.makeStream(of: Step.self)
      let box = DebugLinkBox<RappBleGattPeripheral>()
      let routed = DebugLinkBox<RappBleGattLink>()
      let transport = RappClosureFrameTransport(
        sender: { frame in
          guard let server = box.value, let link = routed.value else {
            throw RappBleGattFailure.disconnected
          }
          try await server.send(frame, on: link)
        },
        closer: { box.value?.cancel() })
      let coordinator: RappPairingCoordinator
      do {
        coordinator = try RappPairingCoordinator.custodian(
          options: options(code: code), transport: transport)
        _ = try coordinator.bootstrapAnswer()
      } catch {
        return DebugModeReport(
          lines: [custodianPrefix + ": the offer could not be made"], succeeded: false)
      }
      let link = RappBleGattPeripheral(
        restoreIdentifier: nil,
        bootstrap: { try? coordinator.bootstrapAnswer() },
        admits: { purpose, link in
          guard purpose == .pairing, routed.value == nil else { return false }
          routed.value = link
          return true
        },
        admitsAttempt: { link in routed.value == link && coordinator.admitsAttempt() },
        onEvent: { event in
          // The ceremony runs on the one link that routed; another
          // central's link ending is not its end.
          switch event {
          case .frame(let link, _), .closed(let link, _):
            guard routed.value == link else { return }

          case .routed, .trace:
            break
          }
          sink.yield(.link(LinkStep(event)))
        })
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
        purpose: .pairing,
        onEvent: { event in
          if let step = LinkStep(event) { sink.yield(.link(step)) }
        })
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
        case .bootstrap(let answer):
          return await pair(
            bootstrap: answer, code: code, transport: transport, steps: steps, sink: sink)

        case .closed(let failure):
          return DebugModeReport(
            lines: [requesterPrefix + ": link closed before the offer: \(failure)"],
            succeeded: false)

        case .trace(let step):
          DebugConsole.emit(requesterPrefix + ": " + step.line)

        case .attemptRefused, .connected, .frame:
          continue
        }
      }
      return DebugModeReport(lines: [requesterPrefix + ": ended"], succeeded: false)
    }

    /// Runs the requester's ceremony from the bootstrap answer it read.
    @MainActor
    private static func pair(
      bootstrap answer: Data,
      code: String,
      transport: any RappFrameTransport,
      steps: AsyncStream<Step>,
      sink: AsyncStream<Step>.Continuation
    ) async -> DebugModeReport {
      let pairingOptions = Self.options(code: code)
      guard
        let bootstrap = try? RappPairingBridge.bootstrapOffer(
          bootstrap: answer, transportProfile: pairingOptions.transportProfile,
          pairingCode: code, startedAtMonotonicMs: pairingOptions.clock.monotonicMilliseconds()),
        let coordinator = try? RappPairingCoordinator.requester(
          options: pairingOptions, transport: transport, bootstrap: bootstrap)
      else {
        return DebugModeReport(
          lines: [requesterPrefix + ": the custodian's offer was refused"], succeeded: false)
      }
      DebugConsole.emit(requesterPrefix + ": read the bootstrap offer")
      return await drive(
        coordinator: coordinator, steps: steps, sink: sink, prefix: requesterPrefix
      ) { await coordinator.start() }
    }

    @MainActor
    private static func options(code: String) -> RappPairingCoordinator.Options {
      RappPairingCoordinator.Options(
        code: code,
        profiles: rappCredentialProfiles(),
        transportProfile: RappBleGattProfile.name,
        displayName: RappPairingModel.localDisplayName,
        platform: RappPairingModel.localPlatform,
        vault: RappDeviceVault())
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

        case .link(.trace(let step)):
          DebugConsole.emit(prefix + ": " + step.line)

        case .pairing(.paired(let summary)):
          return DebugModeReport(
            lines: [prefix + ": paired over " + summary.transportProfile], succeeded: true)

        case .pairing(.closed(let reason)):
          return DebugModeReport(lines: [prefix + ": ceremony ended: \(reason)"], succeeded: false)

        case .timeout:
          await coordinator.close()
          return DebugModeReport(lines: [prefix + ": timed out"], succeeded: false)

        case .link(.attemptRefused), .link(.bootstrap), .pairing:
          // A refused step 1 is reported as the link's close that follows.
          continue
        }
      }
      return DebugModeReport(lines: [prefix + ": ended"], succeeded: false)
    }
  }

#endif
