// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation
  import os
  import RappEngine
  import UIKit

  /// The Bluetooth half of the phone relay: the GATT server of
  /// `fi.refineid.rapp.ble` (RAPP v26.10.29 §5), serving the same pairings
  /// as the stream listener, beside it, and on from the background.
  ///
  /// Each central whose link routes a session preamble gets a session of
  /// its own, beside every other open session on either transport; a
  /// computer is one central with one link, so it holds one session here.
  /// The operating system wakes the app for each write while it is in the
  /// background. Entering the background takes the stream listener down
  /// while Bluetooth serves, since a suspended app cannot answer a dial
  /// (CC-68); the foreground brings it back. Neither is a withdrawal
  /// (§4.5).
  @MainActor
  extension PhonePersistentTokenRelay {
    /// Names the server to iOS state restoration, which relaunches the app
    /// for its Bluetooth events after the system ended the process.
    internal static let bluetoothRestoreIdentifier = "fi.refineid.rapp-ble-custodian"

    /// Admits a link's preamble on the server's queue: a session preamble
    /// routed to a pairing this phone serves (§2.2.1).
    nonisolated private static func admitsBluetooth(
      _ purpose: RappBleRoutingPurpose,
      link: RappBleGattLink,
      routing: OSAllocatedUnfairLock<BluetoothRouting>
    ) -> Bool {
      guard case .session(let preamble) = purpose else {
        #if DEBUG
          DevErrorLog.report(
            "ble link refused: pairing preamble on the session server", source: .app)
        #endif
        return false
      }
      return routing.withLock { state in
        let verdict = state.admission.admit(preamble, transportProfile: RappBleGattProfile.name)
        guard case .open(let index) = verdict else {
          #if DEBUG
            DevErrorLog.report("ble link refused: preamble matches no pairing", source: .app)
          #endif
          return false
        }
        state.routed[link] = state.admission.records[index]
        return true
      }
    }

    /// Serves the pairings in `contexts` over Bluetooth, starting the
    /// server when it is not running.
    internal func startBluetoothServing(_ contexts: [PhoneStreamPairContext]) {
      let records = contexts.map(\.pairRecord)
      bluetoothRouting.withLock { $0.admission.records = records }
      guard bluetoothServer == nil else { return }
      bluetoothRouting.withLock { routing in
        routing.admission.forgetRouted()
        routing.routed.removeAll()
      }
      let routing = bluetoothRouting
      // One stream carries the server's events to the main actor in the
      // order the server reported them: a link's first frame never
      // overtakes its routing.
      let (events, sink) = AsyncStream.makeStream(of: RappBleGattServerEvent.self)
      let server = RappBleGattPeripheral(
        restoreIdentifier: Self.bluetoothRestoreIdentifier,
        bootstrap: nil,
        admits: { purpose, link in
          Self.admitsBluetooth(purpose, link: link, routing: routing)
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
      for session in sessions.values {
        if case .bluetooth = session.transport { session.transportClosed() }
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
    /// operation: idle stream sessions end first, so their requesters dial
    /// again and find Bluetooth; a busy one ends when its operation does.
    internal func suspendStreamWhenIdle() {
      guard streamSuspended, sessionListener != nil else { return }
      let streamSessions = sessions.values.filter { session in
        if case .stream = session.transport { return true }
        return false
      }
      for session in streamSessions where session.isIdle {
        session.close()
      }
      guard streamSessions.allSatisfy(\.isIdle) else { return }
      stopListening()
    }

    private func receiveBluetooth(_ event: RappBleGattServerEvent) {
      switch event {
      case .routed(let link):
        bluetoothRouted(link)

      case .frame(let link, let frame):
        session(on: .bluetooth(link))?.receive(frame)

      case .closed(let link, let failure):
        _ = bluetoothRouting.withLock { $0.routed.removeValue(forKey: link) }
        #if DEBUG
          if failure != .disconnected, failure != .cancelled {
            DevErrorLog.report("ble link closed: \(failure)", source: .app)
          }
        #endif
        session(on: .bluetooth(link))?.transportClosed()

      case .trace(let step):
        traceBluetooth(step)
      }
    }

    /// Opens the session a link routed.
    private func bluetoothRouted(_ link: RappBleGattLink) {
      guard let server = bluetoothServer, sessionListening.withdrawal == nil,
        let pair = bluetoothRouting.withLock({ $0.routed.removeValue(forKey: link) })
      else {
        bluetoothServer?.close(link)
        return
      }
      let frames = RappClosureFrameTransport(
        sender: { [weak server] frame in
          guard let server else { throw RappBleGattFailure.disconnected }
          try await server.send(frame, on: link)
        },
        closer: { [weak server] in server?.close(link) })
      let opened = openSession(
        pair: pair, on: .bluetooth(link), transportProfile: RappBleGattProfile.name,
        frames: frames, earlyFrames: [])
      if opened == nil { server.close(link) }
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
