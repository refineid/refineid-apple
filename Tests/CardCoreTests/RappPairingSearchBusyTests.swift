// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  /// A phone that cannot admit an attempt answers busy, and the requester
  /// asks it again after its wait, quietly, within the connection limit
  /// (RAPP v26.10.29 §4.2, "Busy Refusal"; STPA CC-108).
  @Suite("A requester asks a busy phone again", .timeLimit(.minutes(1)))
  internal struct RappPairingSearchBusyTests {
    // MARK: Nested Types

    private typealias Search = RappPairingSearch<String>

    /// Hands each endpoint's links out in turn, one per dial, and records
    /// the order and time of the dials.
    private final class Dialler: @unchecked Sendable {
      private let lock = NSLock()
      private var links: [String: [@Sendable () -> RappTestPairingLink]]
      private var dials: [(endpoint: String, monotonicMs: UInt64)] = []

      var dialled: [(endpoint: String, monotonicMs: UInt64)] {
        lock.withLock { dials }
      }

      init(_ links: [String: [@Sendable () -> RappTestPairingLink]]) {
        self.links = links
      }

      func dial(_ endpoint: String) -> RappPairingConnection {
        let make = lock.withLock {
          dials.append((endpoint, RappPlatformClock().monotonicMilliseconds()))
          var queue = links[endpoint, default: []]
          let next = queue.count > 1 ? queue.removeFirst() : queue.first
          links[endpoint] = queue
          return next
        }
        return (make?() ?? RappTestPairingLink(servedOffer: nil, dropAfter: dropsAsItOpens))
          .dial()
      }
    }

    // MARK: Static Properties

    /// The code the user types, which the right phone shows.
    private static let typedCode = "246813"
    /// The code another phone in pairing mode shows.
    private static let otherCode = "7KX4M9"
    /// A link that drops as it opens: an endpoint that serves no offer.
    private static let dropsAsItOpens = 0
    /// A busy phone's wait, long enough to tell a reopening that waited.
    private static let busyWait: UInt64 = 200
    /// The least wait a busy answer carries.
    private static let leastBusyWait: UInt64 = 1
    /// Pairing connections one typed code may open (`pairing_candidates_max`,
    /// RAPP v26.10.29 §4.2, "Trying Each Custodian in Pairing Mode" item 5).
    private static let connectionLimit = 8

    // MARK: Static Functions

    private static func prefix(_ testID: String, _ side: String) -> String {
      "fi.refineid.tests.pairing-search-busy.\(testID).\(side)"
    }

    private static func phone(
      showing code: String, testID: String, side: String
    ) async throws -> RappTestPairingPhone {
      try await RappTestPairingPhone.showing(
        code, name: "Phone \(side)", servicePrefix: prefix(testID, side), dropAfter: nil)
    }

    /// A requester searching with `code`, dialling with `dial`.
    private static func search(
      testID: String, code: String, dial: @escaping Search.Dial
    ) throws -> Search {
      let options = RappPairingCoordinator.Options(
        code: code,
        profiles: RappIntegrationFixtures.profiles,
        transportProfile: RappIntegrationFixtures.transportProfile,
        displayName: "Requester Mac",
        platform: "macOS",
        vault: RappDeviceVault(accessGroup: nil, servicePrefix: prefix(testID, "requester")))
      return try Search(options: options, remoteUseAvailable: { true }, dial: dial)
    }

    /// A link serving nothing but a `pairing-busy` asking for `wait`.
    private static func busyLink(wait: UInt64) throws -> RappTestPairingLink {
      RappTestPairingLink(servedOffer: try busyAnswer(wait: wait), dropAfter: nil)
    }

    /// A `pairing-busy` asking for `wait`.
    private static func busyAnswer(wait: UInt64) throws -> Data {
      let custodian = try RappPairingBridge.custodianOffer(
        pairingCode: otherCode, offerId: try RappPlatformEntropy().offerID(),
        profiles: RappIntegrationFixtures.profiles,
        transportProfiles: [RappIntegrationFixtures.transportProfile],
        startedAtMonotonicMs: RappPlatformClock().monotonicMilliseconds())
      return try custodian.busyBytes(
        nowMonotonicMs: RappPlatformClock().monotonicMilliseconds(), spacingWaitMs: wait)
    }

    /// Everything the search reported, once it ended.
    private static func outcome(of search: Search) async -> [Search.Event] {
      var seen: [Search.Event] = []
      for await event in search.events {
        seen.append(event)
      }
      return seen
    }

    private static func clean(_ testID: String, sides: [String]) {
      for side in sides + ["requester"] {
        RappIntegrationConnectionSupport.deleteKeychainServices(prefix: prefix(testID, side))
      }
    }

    /// The refusals the search reported.
    private static func declines(_ events: [Search.Event]) -> [Search.Event] {
      events.filter { event in
        if case .declined = event { return true }
        return false
      }
    }

    private static func pairID(_ events: [Search.Event]) -> Data? {
      for event in events {
        if case .paired(let summary) = event { return summary.pairID }
      }
      return nil
    }

    // MARK: Functions

    @Test("A busy phone is asked again after the other phone and its wait, then pairs")
    internal func aBusyPhoneIsAskedAgain() async throws {
      let testID = UUID().uuidString
      defer { Self.clean(testID, sides: ["other", "right"]) }
      let other = try await Self.phone(showing: Self.otherCode, testID: testID, side: "other")
      let right = try await Self.phone(showing: Self.typedCode, testID: testID, side: "right")
      let busy = try Self.busyLink(wait: Self.busyWait)
      let dialler = Dialler(["right": [{ busy }, { right.link }], "other": [{ other.link }]])
      let search = try Self.search(
        testID: testID, code: Self.typedCode, dial: { dialler.dial($0) })

      await search.found("right")
      await search.found("other")
      let events = await Self.outcome(of: search)

      #expect(events.first == .declined(.refused(.protocolFailure)), "only the other phone refused")
      #expect(
        Self.declines(events) == [.declined(.refused(.protocolFailure))],
        "a busy answer is no refusal of its own")
      let paired = try #require(Self.pairID(events))
      #expect(try right.vault.activePairIDs() == [paired])
      let dials = dialler.dialled
      #expect(dials.map(\.endpoint) == ["right", "other", "right"])
      if let first = dials.first, let last = dials.last {
        #expect(last.monotonicMs >= first.monotonicMs + Self.busyWait, "reopened after its wait")
      }
      #expect(await busy.requesterSent.frames.isEmpty, "no code material to a busy phone")
      _ = await other.close()
      _ = await right.close()
    }

    @Test("A phone still busy at the connection limit is the code not accepted")
    internal func stillBusyAtTheLimit() async throws {
      let testID = UUID().uuidString
      defer { Self.clean(testID, sides: []) }
      let served = try Self.busyAnswer(wait: Self.leastBusyWait)
      let dialler = Dialler([
        "busy": [{ RappTestPairingLink(servedOffer: served, dropAfter: nil) }]
      ])
      let search = try Self.search(
        testID: testID, code: Self.typedCode, dial: { dialler.dial($0) })

      await search.found("busy")
      await search.endDiscovery()
      let events = await Self.outcome(of: search)

      #expect(events == [.closed(.notAccepted)], "nothing shown while it waited")
      #expect(dialler.dialled.count == Self.connectionLimit)
    }

    @Test("Discovery ending while a busy phone is waited for leaves the search to finish")
    internal func discoveryEndsDuringTheWait() async throws {
      let testID = UUID().uuidString
      defer { Self.clean(testID, sides: ["right"]) }
      let right = try await Self.phone(showing: Self.typedCode, testID: testID, side: "right")
      let busy = try Self.busyLink(wait: Self.busyWait)
      let dialler = Dialler(["right": [{ busy }, { right.link }]])
      let search = try Self.search(
        testID: testID, code: Self.typedCode, dial: { dialler.dial($0) })

      await search.found("right")
      await search.endDiscovery()
      let events = await Self.outcome(of: search)

      #expect(Self.pairID(events) != nil, "\(events)")
      #expect(dialler.dialled.map(\.endpoint) == ["right", "right"])
      _ = await right.close()
    }
  }
#endif
