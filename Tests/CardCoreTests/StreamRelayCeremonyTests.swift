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
    private static let streamProfile = rappStreamProfileName()
    private static let profiles = rappCredentialProfiles()

    // MARK: Static Functions

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
          throw RappIntegrationFixtures.TestFailure.pairingClosed(reason)

        case .keyConfirmed, .offerRestored, .peerIntroduced:
          continue
        }
      }
      throw RappIntegrationFixtures.TestFailure.pairingEndedWithoutRecord
    }

    private static func options(
      _ name: String, vault: RappDeviceVault
    ) -> RappPairingCoordinator.Options {
      RappPairingCoordinator.Options(
        code: fixturePairingCode,
        profiles: profiles,
        transportProfile: streamProfile,
        displayName: name,
        platform: name == "Requester" ? "iPadOS" : "iOS",
        vault: vault)
    }

    /// The requester's search, which dials each listener address it is
    /// given over the stream transport.
    private static func makeRequester(vault: RappDeviceVault) throws -> RappPairingSearch<String> {
      try RappPairingSearch(
        options: options("Requester", vault: vault),
        remoteUseAvailable: { true },
        dial: { endpoint in RappPairingConnection.stream(toAddresses: [endpoint]) })
    }

    /// The card holder, which publishes and listens.
    private static func makeProxy(
      vault: RappDeviceVault,
      listener: StreamRelayListener
    ) throws -> RappPairingCoordinator {
      try RappPairingCoordinator.custodian(
        options: options("Proxy", vault: vault),
        transport: RappClosureFrameTransport(
          sender: { frame in try listener.send(frame) },
          closer: { listener.cancel() }))
    }

    /// The pairing the requester's search made.
    private static func awaitPair(
      _ search: RappPairingSearch<String>
    ) async throws -> RappPairingCoordinator.PairSummary {
      for await event in search.events {
        switch event {
        case .paired(let summary):
          return summary

        case .closed(let reason):
          Issue.record("the search ended: \(reason)")
          throw RappIntegrationFixtures.TestFailure.pairingEndedWithoutRecord

        case .declined, .peerIntroduced:
          continue
        }
      }
      throw RappIntegrationFixtures.TestFailure.pairingEndedWithoutRecord
    }

    /// Runs both sides of the ceremony and answers with what each kept.
    ///
    /// The holder serves its offer when the requester's preamble arrives
    /// and is given every frame after it in the order the channel carried
    /// them. A stall here says nothing on its own, so what the holder's side
    /// of the channel carried is reported with the failure.
    private static func pairBothSides(
      requester: RappPairingSearch<String>,
      address: String,
      proxy: RappPairingCoordinator,
      inbound: StreamRelayFrameRelay,
      listener: StreamRelayListener
    ) async throws -> (
      requester: RappPairingCoordinator.PairSummary,
      proxy: RappPairingCoordinator.PairSummary
    ) {
      let delivery = Task {
        await inbound.serve(
          StreamRelayFrameRelay.Receiver(
            arrived: { await proxy.transportConnected() },
            frame: { frame in await proxy.receive(frame) }))
      }
      defer {
        inbound.finish()
        delivery.cancel()
      }
      async let requesterSummary = awaitPair(requester)
      async let proxySummary = awaitPair(proxy)
      await requester.found(address)
      do {
        return try await (requester: requesterSummary, proxy: proxySummary)
      } catch {
        let toProxy = await inbound.summary
        Issue.record(
          """
          listener state: \(listener.state); to proxy: [\(toProxy)]
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
      let listener = StreamRelayListener { event in inbound.report(event) }
      listener.start(displayName: "RefineID ceremony \(testID.prefix(6))")
      defer { listener.cancel() }
      let port = try await Self.boundPort(of: listener)

      let requester = try Self.makeRequester(vault: vaults.requester)
      defer { Task { await requester.close() } }
      let proxy = try Self.makeProxy(vault: vaults.proxy, listener: listener)

      let made = try await Self.pairBothSides(
        requester: requester,
        address: "127.0.0.1:\(port)",
        proxy: proxy,
        inbound: inbound,
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
