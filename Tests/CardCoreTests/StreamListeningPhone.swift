// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  /// A phone in pairing mode on the stream transport, wired as the app
  /// wires it: one listener at a time, a requester admitted by its pairing
  /// preamble, a second dialer answered busy, a busy answer ending only its
  /// connection, and a fresh listener after a failed attempt.
  internal actor StreamListeningPhone {
    // MARK: Properties

    /// The custodian ceremony behind the listeners.
    internal let custodian: RappPairingCoordinator
    /// How many listeners the phone started, the first included.
    internal private(set) var listenersStarted = 0
    /// Requesters admitted by their preamble, per listener, in order.
    internal private(set) var arrivals: [Int] = []

    private let sink: AsyncStream<(Int, StreamRelayEvent)>.Continuation
    private var listener: StreamRelayListener?
    private var admission = StreamPairingAdmission(preamble: rappStreamPairingPreamble())

    // MARK: Lifecycle

    /// A phone showing `code`, keeping its pairing in `vault`.
    internal init(code: String, vault: RappDeviceVault) throws {
      let (events, made) = AsyncStream.makeStream(of: (Int, StreamRelayEvent).self)
      sink = made
      custodian = try RappPairingCoordinator.custodian(
        options: RappPairingCoordinator.Options(
          code: code,
          profiles: rappCredentialProfiles(),
          transportProfile: rappStreamProfileName(),
          displayName: "Phone",
          platform: "iOS",
          vault: vault),
        transport: RappClosureFrameTransport(
          sender: { _ in
            // Replaced by the first listener's transport before any frame.
          },
          closer: {
            // Nothing is open before the first listener starts.
          }))
      let ceremony = custodian
      Task { [weak self] in
        for await (generation, event) in events {
          await self?.handle(event, from: generation)
        }
      }
      Task { [weak self] in
        for await event in ceremony.events where event == .offerRestored {
          await self?.listenAfresh()
        }
      }
    }

    // MARK: Functions

    /// Starts the first listener and the offer.
    internal func start() async {
      await listenAfresh()
      await custodian.start()
    }

    /// The port the current listener bound, once it has.
    internal func port() -> UInt16? {
      listener?.port.flatMap { $0 == 0 ? nil : $0 }
    }

    /// Stops listening and ends the offer.
    internal func stop() async {
      listener?.cancel()
      await custodian.close()
      sink.finish()
    }

    /// A listener of its own, as the app starts one after a failed attempt.
    private func listenAfresh() async {
      listener?.cancel()
      listenersStarted += 1
      arrivals.append(0)
      admission = StreamPairingAdmission(preamble: rappStreamPairingPreamble())
      let generation = listenersStarted
      let ceremony = custodian
      let made = StreamRelayListener(
        busyAnswer: { first in
          first == rappStreamPairingPreamble() ? ceremony.busyAnswer() : nil
        },
        onEvent: { [sink] event in sink.yield((generation, event)) })
      listener = made
      _ = await custodian.replaceTransport(
        RappClosureFrameTransport(
          sender: { frame in try made.send(frame) },
          closer: { made.cancel() },
          connectionEnder: { frame in made.endConnection(answering: frame) }))
      made.start(displayName: "RefineID busy \(generation)")
    }

    private func handle(_ event: StreamRelayEvent, from generation: Int) async {
      guard generation == listenersStarted else { return }
      switch admission.admit(event) {
      case .ignore:
        return

      case .arrive:
        arrivals[generation - 1] += 1
        await custodian.transportConnected()

      case .reject:
        listener?.disconnect()

      case .forward:
        switch event {
        case .frame(let frame):
          await custodian.receive(frame)

        case .closed:
          await custodian.transportClosed()

        case .connected:
          return
        }
      }
    }
  }
#endif
