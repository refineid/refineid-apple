// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  /// A phone serves one offer on the stream and over Bluetooth, and a
  /// requester tries the phones it finds on either (RAPP v26.11.2 §4.2,
  /// "Trying Each Custodian in Pairing Mode" items 1 and 2, "Busy
  /// Refusal" item 2).
  @Suite("A requester pairs over whichever transport reaches the phone", .timeLimit(.minutes(1)))
  internal struct RappPairingSearchTransportsTests {
    // MARK: Nested Types

    private typealias Search = RappPairingSearch<String>

    /// The links each endpoint gives, one per dial, in order.
    private final class Dials: @unchecked Sendable {
      private let lock = NSLock()
      private var queued: [String: [RappTestPairingLink]]

      init(_ queued: [String: [RappTestPairingLink]]) {
        self.queued = queued
      }

      func next(_ endpoint: String) -> RappTestPairingLink {
        lock.withLock {
          guard var links = queued[endpoint], !links.isEmpty else {
            return RappTestPairingLink(servedOffer: nil, dropAfter: dropsAsItOpens)
          }
          let link = links.removeFirst()
          queued[endpoint] = links
          return link
        }
      }
    }

    // MARK: Static Properties

    /// The code the user types, which the right phone shows.
    private static let typedCode = "246813"
    /// The code another phone in pairing mode shows.
    private static let otherCode = "7KX4M9"
    private static let bluetooth = RappBleGattProfile.name
    private static let stream = rappStreamProfileName()
    /// Every transport a phone offers on and a requester pairs over.
    private static let bothTransports = [bluetooth, stream]
    /// A link that drops as it opens: an endpoint that serves no offer.
    private static let dropsAsItOpens = 0
    /// A BLE custodian that served its offer again on the second read
    /// asks for no wait.
    private static let offerServedAgain: UInt64 = 0

    // MARK: Static Functions

    private static func prefix(_ testID: String, _ side: String) -> String {
      "fi.refineid.tests.pairing-transports.\(testID).\(side)"
    }

    private static func options(testID: String) -> RappPairingCoordinator.Options {
      RappPairingCoordinator.Options(
        code: typedCode,
        profiles: RappIntegrationFixtures.profiles,
        transportProfiles: bothTransports,
        displayName: TestDisplayNames.requester,
        platform: "macOS",
        vault: RappDeviceVault(accessGroup: nil, servicePrefix: prefix(testID, "requester")))
    }

    private static func search(testID: String, dials: Dials) throws -> Search {
      try Search(
        options: options(testID: testID),
        remoteUseAvailable: { true },
        dial: { endpoint in dials.next(endpoint).dial() })
    }

    private static func outcome(of search: Search) async -> [Search.Event] {
      var seen: [Search.Event] = []
      for await event in search.events {
        seen.append(event)
      }
      return seen
    }

    private static func summary(_ events: [Search.Event]) -> RappPairingCoordinator.PairSummary? {
      for event in events {
        if case .paired(let summary) = event { return summary }
      }
      return nil
    }

    private static func clean(_ testID: String, sides: [String]) {
      for side in sides + ["requester"] {
        RappIntegrationConnectionSupport.deleteKeychainServices(prefix: prefix(testID, side))
      }
    }

    // MARK: Functions

    @Test("A phone reached only over Bluetooth pairs, bound to Bluetooth")
    internal func bluetoothOnlyPhonePairs() async throws {
      let testID = UUID().uuidString
      defer { Self.clean(testID, sides: ["phone"]) }
      let phone = try await RappTestPairingPhone.showing(
        Self.typedCode, name: "Phone", servicePrefix: Self.prefix(testID, "phone"),
        dropAfter: nil, transportProfiles: Self.bothTransports)
      let unreached = RappTestPairingLink(failingToOpen: .noAnswer)
      let search = try Self.search(
        testID: testID, dials: Dials(["stream": [unreached], "bluetooth": [phone.link]]))

      await search.found("stream")
      await search.found("bluetooth")
      let events = await Self.outcome(of: search)

      #expect(events.first == .declined(.notOpened(.noAnswer)))
      let requester = try #require(Self.summary(events))
      #expect(requester.transportProfile == Self.bluetooth)
      #expect(requester.candidateID == rappCandidateIdentifier(transportProfile: Self.bluetooth))
      let custodian = await phone.close()
      #expect(
        custodian.contains { event in
          if case .paired(let summary) = event {
            return summary.pairID == requester.pairID
              && summary.transportProfile == Self.bluetooth
          }
          return false
        })
    }

    @Test("A phone found on both transports is guessed once")
    internal func oneGuessAcrossTransports() async throws {
      let testID = UUID().uuidString
      defer { Self.clean(testID, sides: ["phone"]) }
      let phone = try await RappTestPairingPhone.showing(
        Self.otherCode, name: "Phone", servicePrefix: Self.prefix(testID, "phone"),
        dropAfter: nil, transportProfiles: [Self.stream, Self.bluetooth])
      let overBluetooth = RappTestPairingLink(
        servedOffer: try phone.offer(), dropAfter: nil, transportProfile: Self.bluetooth)
      let search = try Self.search(
        testID: testID,
        dials: Dials(["stream": [phone.link], "bluetooth": [overBluetooth]]))

      await search.found("stream")
      await search.found("bluetooth")
      let events = await Self.outcome(of: search)

      #expect(
        events == [
          .declined(.refused(.protocolFailure)), .declined(.offerAlreadyTried),
          .closed(.notAccepted),
        ])
      #expect(await overBluetooth.requesterSent.frames.isEmpty, "closed before CPace step 1")
      _ = await phone.close()
    }

    @Test("A Bluetooth phone that refuses step 1 busy is opened again, quietly")
    internal func refusedStepOneIsBusy() async throws {
      let testID = UUID().uuidString
      defer { Self.clean(testID, sides: ["phone"]) }
      let phone = try await RappTestPairingPhone.showing(
        Self.typedCode, name: "Phone", servicePrefix: Self.prefix(testID, "phone"),
        dropAfter: nil, transportProfiles: Self.bothTransports)
      let refusing = RappTestPairingLink(
        servedOffer: try phone.offer(), dropAfter: nil, transportProfile: Self.bluetooth)
      await refusing.answerStepOneBusy(wait: Self.offerServedAgain)
      let search = try Self.search(
        testID: testID, dials: Dials(["bluetooth": [refusing, phone.link]]))

      await search.found("bluetooth")
      let events = await Self.outcome(of: search)

      #expect(
        !events.contains { event in
          if case .declined = event { return true }
          return false
        }, "a busy refusal is not a refusal of the code")
      #expect(Self.summary(events)?.transportProfile == Self.bluetooth)
      _ = await phone.close()
    }

    @Test("A custodian serves one connection at a time, of a transport its offer lists")
    internal func custodianAttachesOneConnection() async throws {
      let testID = UUID().uuidString
      defer { Self.clean(testID, sides: ["phone", "stream-only"]) }
      let streamOnly = try RappPairingCoordinator.custodian(
        options: RappPairingCoordinator.Options(
          code: Self.typedCode, profiles: RappIntegrationFixtures.profiles,
          transportProfiles: [Self.stream], displayName: TestDisplayNames.custodian,
          platform: "iOS",
          vault: RappDeviceVault(
            accessGroup: nil, servicePrefix: Self.prefix(testID, "stream-only"))))
      let unlisted = RappTestPairingLink(servedOffer: nil, dropAfter: nil)
      #expect(
        await !streamOnly.attach(
          unlisted.custodianTransport(), transportProfile: Self.bluetooth))
      await streamOnly.close()

      let phone = try await RappTestPairingPhone.showing(
        Self.typedCode, name: "Phone", servicePrefix: Self.prefix(testID, "phone"),
        dropAfter: nil, transportProfiles: Self.bothTransports)
      let first = RappTestPairingLink(
        servedOffer: nil, dropAfter: nil, transportProfile: Self.bluetooth)
      let second = RappTestPairingLink(servedOffer: nil, dropAfter: nil)
      #expect(
        await phone.custodian.attach(
          first.custodianTransport(), transportProfile: Self.bluetooth))
      await phone.custodian.transportConnected()
      #expect(
        await !phone.custodian.attach(
          second.custodianTransport(), transportProfile: Self.stream),
        "another connection waits while one is served")
      _ = await phone.close()
    }

    @Test("A requester refuses a connection of a transport it does not pair over")
    internal func requesterRefusesAnUnlistedTransport() throws {
      let testID = UUID().uuidString
      defer { Self.clean(testID, sides: ["offer"]) }
      let offered = try RappPairingBridge.custodianOffer(
        pairingCode: Self.typedCode, offerId: try RappPlatformEntropy().offerID(),
        profiles: RappIntegrationFixtures.profiles, transportProfiles: Self.bothTransports,
        startedAtMonotonicMs: RappPlatformClock().monotonicMilliseconds())
      let bootstrap = try RappPairingBridge.bootstrapOffer(
        bootstrap: try offered.bootstrapBytes(
          nowMonotonicMs: RappPlatformClock().monotonicMilliseconds()),
        transportProfile: Self.bluetooth, pairingCode: Self.typedCode,
        startedAtMonotonicMs: RappPlatformClock().monotonicMilliseconds())
      let streamOnly = RappPairingCoordinator.Options(
        code: Self.typedCode, profiles: RappIntegrationFixtures.profiles,
        transportProfiles: [Self.stream], displayName: TestDisplayNames.requester,
        platform: "macOS",
        vault: RappDeviceVault(accessGroup: nil, servicePrefix: Self.prefix(testID, "offer")))
      let link = RappTestPairingLink(servedOffer: nil, dropAfter: nil)
      #expect(throws: RappBindingError.InvalidInput) {
        try RappPairingCoordinator.requester(
          options: streamOnly, transport: link.custodianTransport(),
          transportProfile: Self.bluetooth, bootstrap: bootstrap)
      }
    }
  }
#endif
