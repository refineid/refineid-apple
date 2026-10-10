// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import XCTest

@testable import CardCore

/// The code the custodian fixtures here show.
private let fixturePairingCode = "246813"
/// A code one character away, typed by a requester who misread it.
private let misreadPairingCode = "246814"

#if canImport(RappEngine)
  import RappEngine

  internal final class RappPairingRecoveryTests: XCTestCase {
    private actor RecordingTransport: RappFrameTransport {
      private var frames: [Data] = []
      private var closes = 0

      func send(_ frame: Data) {
        frames.append(frame)
      }

      func close() {
        closes += 1
      }

      func snapshot() -> (frames: [Data], closeCount: Int) {
        (frames, closes)
      }
    }

    private static let transportProfile = rappStreamProfileName()
    private static let profiles = ["fi.refineid.authentication.v1"]
    private static let cpaceRandomByteCount = 64
    /// Longer than the custodian's pre-authentication spacing (§3.3.8).
    private static let reconnectSpacingNanoseconds: UInt64 = 600_000_000

    private func makeCustodian(transport: RecordingTransport) throws -> RappPairingCoordinator {
      try RappPairingCoordinator.custodian(
        options: .init(
          code: fixturePairingCode,
          profiles: Self.profiles,
          transportProfile: Self.transportProfile,
          displayName: "Custodian",
          platform: "iOS",
          vault: RappDeviceVault(accessGroup: nil),
          transport: transport))
    }

    /// A requester bridge keyed on `code` over the offer the custodian
    /// served as its first frame, ready to send Y_A.
    private func makeRequesterBridge(
      code: String, offer: RecordingTransport
    ) async throws -> RappPairingBridge {
      let served = await offer.snapshot().frames
      let encodedOffer = try XCTUnwrap(served.first)
      let bridge = try RappPairingBridge.bootstrapOffer(
        encodedOffer: encodedOffer,
        transportProfile: Self.transportProfile,
        pairingCode: code,
        startedAtMonotonicMs: RappPlatformClock().monotonicMilliseconds())
      try bridge.beginCpace(
        candidateId: try XCTUnwrap(
          rappCandidateIdentifier(transportProfile: Self.transportProfile)),
        randomBytes64: Data(repeating: 0x11, count: Self.cpaceRandomByteCount),
        nowMonotonicMs: RappPlatformClock().monotonicMilliseconds())
      return bridge
    }

    private func collect(
      _ coordinator: RappPairingCoordinator,
      restored: XCTestExpectation,
      closed: XCTestExpectation? = nil
    ) -> Task<RappPairingCoordinator.CloseReason?, Never> {
      let events = coordinator.events
      return Task {
        for await event in events {
          switch event {
          case .offerRestored:
            restored.fulfill()

          case .closed(let reason):
            closed?.fulfill()
            return reason

          case .peerIntroduced, .paired:
            continue
          }
        }
        return nil
      }
    }

    internal func testCustodianKeepsItsOfferAfterAnInvalidFirstMessage() async throws {
      let restored = expectation(description: "offer restored")
      let firstTransport = RecordingTransport()
      let custodian = try makeCustodian(transport: firstTransport)
      let collector = collect(custodian, restored: restored)

      await custodian.transportConnected()
      await custodian.receive(Data(count: 32))
      await fulfillment(of: [restored], timeout: 2)
      let firstSnapshot = await firstTransport.snapshot()
      XCTAssertEqual(firstSnapshot.frames.count, 1)
      XCTAssertEqual(firstSnapshot.closeCount, 1)

      try await Task.sleep(nanoseconds: Self.reconnectSpacingNanoseconds)
      let replacement = RecordingTransport()
      let replaced = await custodian.replaceTransport(replacement)
      XCTAssertTrue(replaced)
      await custodian.transportConnected()
      let requester = try await makeRequesterBridge(code: fixturePairingCode, offer: replacement)
      await custodian.receive(
        try requester.writeCpaceFrame(nowMonotonicMs: RappPlatformClock().monotonicMilliseconds()))
      let replacementSnapshot = await replacement.snapshot()
      XCTAssertEqual(replacementSnapshot.frames.count, 2)
      XCTAssertEqual(replacementSnapshot.frames.first, firstSnapshot.frames.first)
      await custodian.close()
      collector.cancel()
    }

    internal func testCustodianServesTheOfferOnceItConnects() async throws {
      let transport = RecordingTransport()
      let custodian = try makeCustodian(transport: transport)
      await custodian.transportConnected()
      let frames = await transport.snapshot().frames
      XCTAssertEqual(frames.count, 1)
      let offer = try XCTUnwrap(frames.first)
      XCTAssertNoThrow(
        try RappPairingBridge.bootstrapOffer(
          encodedOffer: offer, transportProfile: Self.transportProfile,
          pairingCode: fixturePairingCode,
          startedAtMonotonicMs: RappPlatformClock().monotonicMilliseconds()))
      await custodian.close()
    }

    internal func testASecondConnectionWithinTheSpacingIsClosedUnserved() async throws {
      let restored = expectation(description: "offer restored after each connection")
      restored.expectedFulfillmentCount = 2
      let first = RecordingTransport()
      let custodian = try makeCustodian(transport: first)
      let collector = collect(custodian, restored: restored)

      await custodian.transportConnected()
      await custodian.receive(Data(count: 32))
      let second = RecordingTransport()
      let replaced = await custodian.replaceTransport(second)
      XCTAssertTrue(replaced)
      await custodian.transportConnected()

      let refused = await second.snapshot()
      XCTAssertTrue(refused.frames.isEmpty)
      XCTAssertEqual(refused.closeCount, 1)
      await fulfillment(of: [restored], timeout: 2)
      await custodian.close()
      collector.cancel()
    }

    internal func testThreeMisreadCodesLockTheOffer() async throws {
      let restored = expectation(description: "offer restored after each failed attempt")
      restored.expectedFulfillmentCount = 2
      let closed = expectation(description: "offer locked")
      let firstTransport = RecordingTransport()
      let custodian = try makeCustodian(transport: firstTransport)
      let collector = collect(custodian, restored: restored, closed: closed)

      for attempt in 1...3 {
        var transport = firstTransport
        if attempt > 1 {
          try await Task.sleep(nanoseconds: Self.reconnectSpacingNanoseconds)
          transport = RecordingTransport()
          let replaced = await custodian.replaceTransport(transport)
          XCTAssertTrue(replaced)
        }
        await custodian.transportConnected()
        let requester = try await makeRequesterBridge(code: misreadPairingCode, offer: transport)
        await custodian.receive(
          try requester.writeCpaceFrame(
            nowMonotonicMs: RappPlatformClock().monotonicMilliseconds()))
        // The requester sees T_B fail and drops the link without sending T_A.
        await custodian.transportClosed()
      }

      await fulfillment(of: [restored, closed], timeout: 2)
      let reason = await collector.value
      XCTAssertEqual(reason, .attemptsExhausted)
    }
  }
#endif
