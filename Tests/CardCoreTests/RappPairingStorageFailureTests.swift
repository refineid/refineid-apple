// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import XCTest

@testable import CardCore

/// The code the custodian fixture here shows.
private let fixturePairingCode = "246813"

#if canImport(RappEngine)
  import RappEngine

  /// A custodian that stored its record and then hears nonsense instead of
  /// the peer's `pairing.stored` revokes the record (RAPP v26.10.29 §4.3
  /// item 4).
  internal final class RappPairingStorageFailureTests: XCTestCase {
    private actor RecordingTransport: RappFrameTransport {
      private var frames: [Data] = []

      func send(_ frame: Data) {
        frames.append(frame)
      }

      func close() {
        // The custodian under test owns no socket.
      }

      func snapshot() -> [Data] {
        frames
      }
    }

    private static let transportProfile = rappStreamProfileName()
    private static let profiles = rappCredentialProfiles()

    private var now: UInt64 { RappPlatformClock().monotonicMilliseconds() }

    /// The frame the custodian sent last.
    private func lastFrame(_ transport: RecordingTransport, expecting count: Int) async throws
      -> Data
    {
      let frames = await transport.snapshot()
      XCTAssertEqual(frames.count, count)
      return try XCTUnwrap(frames.last)
    }

    /// Runs the ceremony as the requester until the custodian has stored
    /// its record and sent `pairing.stored`.
    private func driveToStorage(
      _ custodian: RappPairingCoordinator, transport: RecordingTransport
    ) async throws {
      await custodian.transportConnected()
      let offer = try await lastFrame(transport, expecting: 1)
      let requester = try RappPairingBridge.bootstrapOffer(
        encodedOffer: offer, transportProfile: Self.transportProfile,
        pairingCode: fixturePairingCode, startedAtMonotonicMs: now)
      try requester.beginCpace(
        candidateId: try XCTUnwrap(
          rappCandidateIdentifier(transportProfile: Self.transportProfile)),
        randomBytes64: try RappPlatformEntropy().cpaceRandom(),
        nowMonotonicMs: now)

      await custodian.receive(try requester.writeCpaceFrame(nowMonotonicMs: now))
      try requester.readCpaceFrame(
        bytes: try await lastFrame(transport, expecting: 2), nowMonotonicMs: now)
      await custodian.receive(try requester.writeCpaceFrame(nowMonotonicMs: now))
      await custodian.receive(try requester.writeHandshakeFrame(nowMonotonicMs: now))
      try requester.readHandshakeFrame(
        bytes: try await lastFrame(transport, expecting: 3), nowMonotonicMs: now)
      await custodian.receive(try requester.writeHandshakeFrame(nowMonotonicMs: now))
      try requester.enterConfirmation(nowMonotonicMs: now)
      await custodian.receive(
        try requester.sendHello(displayName: "Mac", platform: "macOS", nowMonotonicMs: now))
      let answered = await transport.snapshot()
      XCTAssertEqual(answered.count, 5)
      _ = try requester.receiveHello(bytes: answered[3], nowMonotonicMs: now)
      let granted = try requester.receiveConfirmation(bytes: answered[4], nowMonotonicMs: now)
      await custodian.receive(
        try requester.sendConfirmation(grantedProfiles: granted, nowMonotonicMs: now))
    }

    internal func testNonsenseInsteadOfPeerStorageRevokesTheStoredRecord() async throws {
      let vault = RappDeviceVault(
        accessGroup: nil, servicePrefix: "fi.refineid.test.storage.\(UUID().uuidString)")
      defer { _ = try? vault.deleteServiceNamespace("fi.refineid.test.storage") }
      let transport = RecordingTransport()
      let custodian = try RappPairingCoordinator.custodian(
        options: .init(
          code: fixturePairingCode,
          profiles: Self.profiles,
          transportProfile: Self.transportProfile,
          displayName: "Custodian",
          platform: "iOS",
          vault: vault),
        transport: transport)
      let ended = expectation(description: "the attempt ended")
      let events = custodian.events
      let collector = Task {
        for await event in events {
          if case .paired = event { continue }
          if case .peerIntroduced = event { continue }
          ended.fulfill()
          return
        }
      }
      defer { collector.cancel() }

      try await driveToStorage(custodian, transport: transport)

      // The custodian has stored its record and told the peer.
      _ = try await lastFrame(transport, expecting: 6)
      let stored = try vault.activePairIDs()
      XCTAssertEqual(stored.count, 1)
      let pairID = try XCTUnwrap(stored.first)

      await custodian.receive(Data("not a pairing.stored frame".utf8))
      await fulfillment(of: [ended], timeout: 2)
      XCTAssertEqual(try vault.activePairIDs(), [])
      XCTAssertNil(try vault.loadPair(pairID: pairID))
      await custodian.close()
    }
  }
#endif
