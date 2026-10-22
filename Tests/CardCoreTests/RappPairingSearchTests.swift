// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  /// The requester tries every phone in pairing mode with the typed code
  /// before it calls the code not accepted (RAPP v26.10.22 §4.2, "Trying
  /// Each Custodian in Pairing Mode"; STPA CC-83).
  @Suite("A requester tries every phone in pairing mode", .timeLimit(.minutes(1)))
  internal struct RappPairingSearchTests {
    // MARK: Nested Types

    private typealias Search = RappPairingSearch<String>

    // MARK: Static Properties

    /// The code the user types, which the right phone shows.
    private static let typedCode = "246813"
    /// The code another phone in pairing mode shows.
    private static let otherCode = "7KX4M9"
    /// A phone's link that drops once the phone sent its offer and CPace
    /// step 2: after T_B, before the handshake.
    private static let framesThroughStepTwo = 2
    /// A link that drops as it opens: an endpoint that serves no offer.
    private static let dropsAsItOpens = 0

    // MARK: Static Functions

    private static func prefix(_ testID: String, _ side: String) -> String {
      "fi.refineid.tests.pairing-search.\(testID).\(side)"
    }

    private static func phone(
      showing code: String, testID: String, side: String, dropAfter: Int?
    ) async throws -> RappTestPairingPhone {
      try await RappTestPairingPhone.showing(
        code, name: "Phone \(side)", servicePrefix: prefix(testID, side), dropAfter: dropAfter)
    }

    /// A requester searching with the typed code, dialling the named links.
    private static func search(
      testID: String, links: [String: RappTestPairingLink]
    ) throws -> Search {
      let options = RappPairingCoordinator.Options(
        code: typedCode,
        profiles: RappIntegrationFixtures.profiles,
        transportProfile: RappIntegrationFixtures.transportProfile,
        displayName: "Requester Mac",
        platform: "macOS",
        vault: RappDeviceVault(accessGroup: nil, servicePrefix: prefix(testID, "requester")))
      return try Search(options: options) { endpoint in
        links[endpoint, default: RappTestPairingLink(servedOffer: nil, dropAfter: dropsAsItOpens)]
          .dial()
      }
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

    private static func pairID(_ events: [Search.Event]) -> Data? {
      for event in events {
        if case .paired(let summary) = event { return summary.pairID }
      }
      return nil
    }

    // MARK: Functions

    @Test("The phone that shows the code pairs after another phone refused it")
    internal func theRightPhonePairsAfterARefusal() async throws {
      let testID = UUID().uuidString
      defer { Self.clean(testID, sides: ["other", "right"]) }
      let other = try await Self.phone(
        showing: Self.otherCode, testID: testID, side: "other", dropAfter: nil)
      let right = try await Self.phone(
        showing: Self.typedCode, testID: testID, side: "right", dropAfter: nil)
      let search = try Self.search(
        testID: testID, links: ["other": other.link, "right": right.link])

      await search.found("other")
      await search.found("right")
      let events = await Self.outcome(of: search)

      #expect(events.first == .declined(.refused(.protocolFailure)))
      #expect(!events.contains(.closed(.notAccepted)), "no wrong-code message")
      let paired = try #require(Self.pairID(events))
      #expect(try right.vault.activePairIDs() == [paired])
      #expect(try other.vault.activePairIDs().isEmpty)
      let otherOutcomes = await other.close()
      #expect(
        otherOutcomes.contains(.offerRestored),
        "the other phone keeps its offer, one attempt spent")
      let rightOutcomes = await right.close()
      #expect(
        rightOutcomes.contains { event in
          if case .paired(let summary) = event { return summary.pairID == paired }
          return false
        })
    }

    @Test("The code is not accepted only once every phone tried refused it")
    internal func everyPhoneRefused() async throws {
      let testID = UUID().uuidString
      defer { Self.clean(testID, sides: ["first", "second"]) }
      let first = try await Self.phone(
        showing: Self.otherCode, testID: testID, side: "first", dropAfter: nil)
      let second = try await Self.phone(
        showing: Self.otherCode, testID: testID, side: "second", dropAfter: nil)
      let search = try Self.search(
        testID: testID, links: ["first": first.link, "second": second.link])

      await search.found("first")
      await search.found("second")
      let events = await Self.outcome(of: search)

      #expect(
        events == [
          .declined(.refused(.protocolFailure)), .declined(.refused(.protocolFailure)),
          .closed(.notAccepted),
        ])
      #expect(await first.link.isOpened)
      #expect(await second.link.isOpened)
      _ = await first.close()
      _ = await second.close()
    }

    @Test("A search that tried no phone found none in pairing mode")
    internal func noPhoneTried() async throws {
      let testID = UUID().uuidString
      defer { Self.clean(testID, sides: []) }
      let silent = RappTestPairingLink(servedOffer: nil, dropAfter: Self.dropsAsItOpens)
      let search = try Self.search(testID: testID, links: ["no offer": silent])

      await search.found("no offer")
      var events: [Search.Event] = []
      for await event in search.events {
        events.append(event)
        if event == .declined(.noOffer) {
          await search.endDiscovery()
        }
      }

      #expect(events == [.declined(.noOffer), .closed(.noneInPairingMode)])
      #expect(await silent.isOpened)

      let empty = try Self.search(testID: testID, links: [:])
      await empty.endDiscovery()
      #expect(await Self.outcome(of: empty) == [.closed(.noneInPairingMode)])
    }

    @Test("A phone found again under another name gets no second guess")
    internal func oneGuessPerOffer() async throws {
      let testID = UUID().uuidString
      defer { Self.clean(testID, sides: ["phone"]) }
      let phone = try await Self.phone(
        showing: Self.otherCode, testID: testID, side: "phone", dropAfter: nil)
      let copy = RappTestPairingLink(servedOffer: try await phone.offer(), dropAfter: nil)
      let search = try Self.search(testID: testID, links: ["phone": phone.link, "copy": copy])

      await search.found("phone")
      await search.found("copy")
      let events = await Self.outcome(of: search)

      #expect(
        events == [
          .declined(.refused(.protocolFailure)), .declined(.offerAlreadyTried),
          .closed(.notAccepted),
        ])
      let sentToCopy = await copy.requesterSent
      #expect(sentToCopy.frames.isEmpty, "closed before CPace step 1")
      #expect(sentToCopy.closeCount == 1)
      _ = await phone.close()
    }

    @Test("A verified T_B ends the search: a later failure tries no other phone")
    internal func acceptanceEndsTheSearch() async throws {
      let testID = UUID().uuidString
      defer { Self.clean(testID, sides: ["first", "second"]) }
      let first = try await Self.phone(
        showing: Self.typedCode, testID: testID, side: "first",
        dropAfter: Self.framesThroughStepTwo)
      let second = try await Self.phone(
        showing: Self.typedCode, testID: testID, side: "second", dropAfter: nil)
      let search = try Self.search(
        testID: testID, links: ["first": first.link, "second": second.link])

      await search.found("first")
      await search.found("second")
      let events = await Self.outcome(of: search)

      #expect(events == [.closed(.ceremonyEnded(.transportFailure))])
      #expect(await !second.link.isOpened)
      _ = await first.close()
      _ = await second.close()
    }

    @Test("A phone that does not answer CPace step 1 in time is given up")
    internal func silentPhoneIsGivenUp() async throws {
      let testID = UUID().uuidString
      defer { Self.clean(testID, sides: ["mute", "right"]) }
      let mute = try await Self.phone(
        showing: Self.typedCode, testID: testID, side: "mute", dropAfter: nil)
      let unanswered = RappTestPairingLink(servedOffer: try await mute.offer(), dropAfter: nil)
      let right = try await Self.phone(
        showing: Self.typedCode, testID: testID, side: "right", dropAfter: nil)
      let search = try Self.search(
        testID: testID, links: ["unanswered": unanswered, "right": right.link])

      await search.found("unanswered")
      await search.found("right")
      let events = await Self.outcome(of: search)

      #expect(events.first == .declined(.refused(.attemptTimedOut)))
      #expect(Self.pairID(events) != nil)
      _ = await mute.close()
      _ = await right.close()
    }
  }
#endif
