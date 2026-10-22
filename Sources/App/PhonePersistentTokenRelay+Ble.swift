// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD && REFINEID_STREAM_TRANSPORT
  import CardCore
  import Foundation
  import os
  import RappEngine
  import UIKit

  /// The Bluetooth half of the phone relay: the GATT server of
  /// `fi.refineid.rapp.ble` (RAPP v26.10.22 §5), serving the same pairings
  /// as the stream listener, beside it, and on from the background.
  ///
  /// A central routes a session preamble on its link; the phone serves one
  /// session at a time whatever transport carries it (CC-67), and the
  /// operating system wakes the app for each write while it is in the
  /// background. Entering the background takes the stream listener down
  /// while Bluetooth serves, since a suspended app cannot answer a dial
  /// (CC-68); the foreground brings it back. Neither is a withdrawal
  /// (§4.5).
  @MainActor
  extension PhonePersistentTokenRelay {
    /// Names the server to iOS state restoration, which relaunches the app
    /// for its Bluetooth events after the system ended the process.
    internal static let bluetoothRestoreIdentifier = "fi.refineid.rapp-ble-custodian"

    /// Admits a link's preamble on the server's queue.
    ///
    /// A session preamble routed to a pairing this phone serves (§2.2.1),
    /// with the one-session gate (CC-67) open to it. The main actor decides
    /// again before it displaces anything.
    nonisolated private static func admitsBluetooth(
      _ purpose: RappBleRoutingPurpose,
      link: RappBleGattLink,
      routing: OSAllocatedUnfairLock<BluetoothRouting>,
      serving: OSAllocatedUnfairLock<(pairing: Data?, idleSince: ContinuousClock.Instant?)>,
      holdSeconds: Int64
    ) -> Bool {
      guard case .session(let preamble) = purpose else {
        #if DEBUG
          DevErrorLog.report(
            "ble link refused: pairing preamble on the session server", source: .app)
        #endif
        return false
      }
      let (pairing, idleSince) = serving.withLock { $0 }
      return routing.withLock { state in
        let route = state.router.route(
          transportProfile: RappBleGattProfile.name, preamble: preamble, records: state.records)
        guard case .session(let index) = route, state.records.indices.contains(index) else {
          #if DEBUG
            DevErrorLog.report("ble link refused: preamble matches no pairing", source: .app)
          #endif
          return false
        }
        let incoming = state.records[index]
        let verdict = HolderSessionAdmission.decide(
          incoming: incoming.metadata().pairId, pairing: pairing, idleSince: idleSince,
          now: .now, hold: .seconds(holdSeconds))
        guard verdict.admits else {
          #if DEBUG
            DevErrorLog.report("ble link refused: \(verdict)", source: .app)
          #endif
          return false
        }
        state.routed[link] = incoming
        return true
      }
    }

    /// Serves the pairings in `contexts` over Bluetooth, starting the
    /// server when it is not running.
    internal func startBluetoothServing(_ contexts: [PhoneStreamPairContext]) {
      let records = contexts.map(\.pairRecord)
      bluetoothRouting.withLock { $0.records = records }
      guard bluetoothServer == nil else { return }
      bluetoothRouting.withLock { routing in
        routing.router = RappSessionRouter()
        routing.routed.removeAll()
      }
      let routing = bluetoothRouting
      let serving = sessionServing
      let holdSeconds = Self.crossPeerHoldSeconds
      // One stream carries the server's events to the main actor in the
      // order the server reported them: a link's first frame never
      // overtakes its routing.
      let (events, sink) = AsyncStream.makeStream(of: RappBleGattServerEvent.self)
      let server = RappBleGattPeripheral(
        restoreIdentifier: Self.bluetoothRestoreIdentifier,
        bootstrapOffer: nil,
        admits: { purpose, link in
          Self.admitsBluetooth(
            purpose, link: link, routing: routing, serving: serving, holdSeconds: holdSeconds)
        },
        onEvent: { event in sink.yield(event) })
      bluetoothServer = server
      bluetoothEvents = Task { [weak self] in
        for await event in events {
          self?.receiveBluetooth(event)
        }
      }
      server.start()
    }

    /// Stops the server: no advertisement, no service, no link.
    internal func stopBluetoothServing() {
      bluetoothEvents?.cancel()
      bluetoothEvents = nil
      bluetoothServer?.cancel()
      bluetoothServer = nil
      bluetoothAdvertising = false
      bluetoothRouting.withLock { $0.routed.removeAll() }
    }

    /// Re-decides on the main actor whether a dial routed to `incoming`
    /// gets the session, and displaces the open one when it does (CC-67):
    /// two transports racing for an empty slot cannot both win.
    internal func admitSession(for incoming: Data) -> Bool {
      let (pairing, idleSince) = sessionServing.withLock { $0 }
      let verdict = HolderSessionAdmission.decide(
        incoming: incoming, pairing: pairing, idleSince: idleSince, now: .now,
        hold: .seconds(Self.crossPeerHoldSeconds))
      guard verdict.admits else {
        #if DEBUG
          DevErrorLog.report("dial refused: \(verdict)", source: .app)
        #endif
        return false
      }
      if coordinator != nil {
        dropServedTransport()
        handleConnectionClosed()
        RappAuthorizationInbox.shared.cancelAll()
      }
      return true
    }

    /// Ends the open session's transport: its stream connection or its
    /// Bluetooth link.
    internal func dropServedTransport() {
      switch servedTransport {
      case .stream:
        activeStreamListener?.disconnect()

      case .bluetooth(let link):
        bluetoothServer?.close(link)

      case nil:
        break
      }
    }

    /// Follows the app into and out of the background.
    internal func observeLifecycle() {
      let center = NotificationCenter.default
      lifecycleObservers = [
        center.addObserver(
          forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in
          MainActor.assumeIsolated { Self.shared.enteredBackground() }
        },
        center.addObserver(
          forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { _ in
          MainActor.assumeIsolated { Self.shared.enteringForeground() }
        },
      ]
    }

    /// Takes the stream listener down for the background while Bluetooth
    /// serves (CC-68).
    private func enteredBackground() {
      guard bluetoothAdvertising, isServing else { return }
      #if DEBUG
        HolderTrace.say("background: stream suspended, Bluetooth serves")
      #endif
      streamSuspended = true
      suspendStreamWhenIdle()
    }

    /// Publishes the stream listener again.
    private func enteringForeground() {
      guard streamSuspended else { return }
      #if DEBUG
        HolderTrace.say("foreground: stream resumes")
      #endif
      streamSuspended = false
      start()
    }

    /// Takes the stream listener down once no stream session carries an
    /// operation; an idle stream session ends first, so its requester
    /// dials again and finds Bluetooth.
    internal func suspendStreamWhenIdle() {
      guard streamSuspended, !streamListeners.isEmpty else { return }
      if servedTransport == .stream {
        guard sessionServing.withLock({ $0.idleSince }) != nil else { return }
        handleConnectionClosed()
      }
      pruneStreamTransports(keeping: [])
    }

    private func receiveBluetooth(_ event: RappBleGattServerEvent) {
      switch event {
      case .routed(let link):
        bluetoothRouted(link)

      case .frame(let link, let frame):
        guard servedTransport == .bluetooth(link) else { return }
        if let coordinator {
          deliverInOrder { await coordinator.receive(frame) }
        } else if preCoordinatorFrames.count < Self.maximumPreCoordinatorFrames {
          preCoordinatorFrames.append(frame)
        } else {
          bluetoothServer?.close(link)
        }

      case .closed(let link, let failure):
        _ = bluetoothRouting.withLock { $0.routed.removeValue(forKey: link) }
        #if DEBUG
          if failure != .disconnected, failure != .cancelled {
            DevErrorLog.report("ble link closed: \(failure)", source: .app)
          }
        #endif
        guard servedTransport == .bluetooth(link) else { return }
        handleConnectionClosed()
        RappAuthorizationInbox.shared.cancelAll()

      case .trace(let step):
        traceBluetooth(step)
      }
    }

    /// Opens the session a link routed, once the main actor admits it too.
    private func bluetoothRouted(_ link: RappBleGattLink) {
      guard let server = bluetoothServer, sessionListening.withdrawal == nil,
        let pair = bluetoothRouting.withLock({ $0.routed.removeValue(forKey: link) }),
        admitSession(for: pair.metadata().pairId)
      else {
        bluetoothServer?.close(link)
        return
      }
      let routedConnectionID = UUID()
      connectionID = routedConnectionID
      servedTransport = .bluetooth(link)
      PairLastUse.markUsed(pairID: pair.metadata().pairId, at: Date())
      let transport = RappClosureFrameTransport(
        sender: { [weak server] frame in
          guard let server else { throw RappBleGattFailure.disconnected }
          try await server.send(frame, on: link)
        },
        closer: { [weak server] in server?.close(link) })
      establishCoordinator(
        connectionID: routedConnectionID, pair: pair, transportProfile: RappBleGattProfile.name,
        transport: transport
      ) { [weak server] in
        server?.close(link)
      }
      if coordinator == nil {
        servedTransport = nil
        connectionID = nil
      }
    }

    /// Follows the server's advertising, and in a development build writes
    /// each step to the trace and each failure to the error strip.
    private func traceBluetooth(_ step: RappBleGattTrace) {
      switch step {
      case .advertisingStarted:
        bluetoothAdvertising = true

      case .advertisingStopped, .advertisingFailed, .radio(.poweredOff), .radio(.resetting),
        .radio(.unauthorized), .radio(.unsupported):
        bluetoothAdvertising = false

      default:
        break
      }
      #if DEBUG
        HolderTrace.say("ble \(step.line)")
        switch step {
        case .advertisingFailed, .serviceNotPublished, .radio(.unauthorized),
          .radio(.unsupported), .radio(.poweredOff):
          DevErrorLog.report("ble server: \(step.line)", source: .app)

        case .subscribed(_, let attMtu) where attMtu < RappBleSar.minimumAttMtu:
          DevErrorLog.report("ble link: ATT MTU \(attMtu) below the minimum", source: .app)

        default:
          break
        }
      #endif
    }
  }
#endif
