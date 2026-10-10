// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// The six-character code the two fixtures here key their CPace PAKE on.
private let fixturePairingCode = "246813"

#if canImport(RappEngine)
  import RappEngine
  /// The reader's ceremony, over the transport the devices use.
  ///
  /// Everything here is real: a pairing made over a listener and a dialled
  /// port, and the records both sides keep from it. This is what the two
  /// devices could not do, because the ceremony ran over a framework that
  /// would not carry it and only one side kept a record.
  @Suite
  internal struct StreamRelayCeremonyTests {
    // MARK: Static Properties

    private static let attempts = 150
    private static let pause = Duration.milliseconds(100)
    private static let streamProfile = "fi.refineid.stream.v1"
    private static let profiles = [
      "fi.refineid.card-status.v1",
      "fi.refineid.authentication.v1",
    ]

    // MARK: Static Functions

    /// Waits until the channel reports the peer has arrived.
    ///
    /// A ceremony started before that speaks into a channel with no peer on
    /// it, and its first message is lost.
    private static func awaitConnected(_ relay: StreamRelayFrameRelay) async throws {
      for _ in 0..<attempts {
        if await relay.connected { return }
        try await Task.sleep(for: pause)
      }
      throw StreamRelayTestFailure.noFrame
    }

    /// Waits for the listener to bind a port that can actually be dialled.
    private static func boundPort(of listener: StreamRelayListener) async throws -> UInt16 {
      for _ in 0..<attempts {
        if let port = listener.port, port != 0 { return port }
        try await Task.sleep(for: pause)
      }
      throw StreamRelayTestFailure.noFrame
    }

    /// Answers with the pairing that resulted.
    private static func awaitPair(
      _ coordinator: RappPairingCoordinator
    ) async throws -> RappPairingCoordinator.PairSummary {
      for await event in coordinator.events {
        switch event {
        case .paired(let summary):
          return summary

        case .closed(let reason):
          throw SignRelayPairingFailure.closed(String(describing: reason))

        case .peerIntroduced, .offerRestored:
          continue
        }
      }
      throw SignRelayPairingFailure.endedWithoutRecord
    }

    private static func options(
      _ name: String, vault: RappDeviceVault, transport: RappClosureFrameTransport
    ) -> RappPairingCoordinator.Options {
      RappPairingCoordinator.Options(
        code: fixturePairingCode,
        profiles: profiles,
        transportProfile: streamProfile,
        displayName: name,
        platform: name == "Requester" ? "iPadOS" : "iOS",
        vault: vault,
        transport: transport)
    }

    /// The requester, which dials what it found.
    private static func makeRequester(
      vault: RappDeviceVault,
      dialer: StreamRelaySession
    ) throws -> RappPairingCoordinator {
      try RappPairingCoordinator.requester(
        options: options(
          "Requester", vault: vault,
          transport: RappClosureFrameTransport(
            sender: { frame in try await dialer.send(frame) },
            closer: { dialer.cancel() })))
    }

    /// The card holder, which publishes and listens.
    private static func makeProxy(
      vault: RappDeviceVault,
      listener: StreamRelayListener
    ) throws -> RappPairingCoordinator {
      try RappPairingCoordinator.custodian(
        options: options(
          "Proxy", vault: vault,
          transport: RappClosureFrameTransport(
            sender: { frame in try listener.send(frame) },
            closer: { listener.cancel() })))
    }

    /// Runs both sides of the ceremony and answers with what each kept.
    ///
    /// A stall here says nothing on its own, so what each side of the
    /// channel carried is reported with the failure.
    private static func pairBothSides(
      requester: RappPairingCoordinator,
      proxy: RappPairingCoordinator,
      inbound: StreamRelayFrameRelay,
      outbound: StreamRelayFrameRelay,
      listener: StreamRelayListener
    ) async throws -> (
      requester: RappPairingCoordinator.PairSummary,
      proxy: RappPairingCoordinator.PairSummary
    ) {
      async let requesterSummary = awaitPair(requester)
      async let proxySummary = awaitPair(proxy)
      try await awaitConnected(inbound)
      try await awaitConnected(outbound)
      // The requester waits for the offer the custodian serves on connecting.
      await requester.transportConnected()
      await proxy.transportConnected()
      do {
        return try await (requester: requesterSummary, proxy: proxySummary)
      } catch {
        let toRequester = await inbound.summary
        let toProxy = await outbound.summary
        Issue.record(
          """
          listener state: \(listener.state); \
          to requester: [\(toRequester)]; to proxy: [\(toProxy)]
          """)
        throw error
      }
    }

    // MARK: Functions

    /// Both sides keep a record of one pairing made over the stream
    /// transport.
    ///
    /// A pairing only one side keeps is worse than none: it looks made and
    /// cannot be used, which is exactly what these devices were left with.
    @Test
    internal func bothSidesKeepOnePairingMadeOverTheStream() async throws {
      let testID = UUID().uuidString
      let vaults = StreamRelayCeremonyVaults(testID: testID)
      defer { vaults.clean() }

      let inbound = StreamRelayFrameRelay()
      let listener = StreamRelayListener { event in
        Task { await inbound.deliver(event) }
      }
      listener.start(displayName: "RefineID ceremony \(testID.prefix(6))")
      defer { listener.cancel() }
      let port = try await Self.boundPort(of: listener)

      let outbound = StreamRelayFrameRelay()
      let dialer = StreamRelaySession(
        endpointLiterals: ["127.0.0.1:\(port)"],
        preamble: rappStreamPairingPreamble()
      ) { event in
        Task { await outbound.deliver(event) }
      }
      dialer.start()
      defer { dialer.cancel() }

      let requester = try Self.makeRequester(vault: vaults.requester, dialer: dialer)
      let proxy = try Self.makeProxy(vault: vaults.proxy, listener: listener)

      await inbound.install { frame in await proxy.receive(frame) }
      await outbound.install { frame in await requester.receive(frame) }

      let made = try await Self.pairBothSides(
        requester: requester,
        proxy: proxy,
        inbound: inbound,
        outbound: outbound,
        listener: listener)

      #expect(
        made.requester.pairID == made.proxy.pairID,
        "the two sides kept different pairings")
      #expect(
        try vaults.requester.activePairIDs().contains(made.requester.pairID),
        "the requester kept no record of the pairing it made")
      #expect(
        try vaults.proxy.activePairIDs().contains(made.proxy.pairID),
        "the holder kept no record of the pairing it made")
    }
  }
#endif
