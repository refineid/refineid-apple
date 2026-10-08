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

    private static let candidateID = "candidate"
    private static let profiles = ["fi.refineid.authentication.v1"]
    private static let cpaceRandomByteCount = 64

    private static var candidate: RappPairingCoordinator.TransportCandidate {
      .init(profile: "local-quic-v1", candidateID: candidateID, parametersCBOR: Data([0xa0]))
    }

    private func makeCustodian(transport: RecordingTransport) throws -> RappPairingCoordinator {
      try RappPairingCoordinator.custodian(
        options: .init(
          code: fixturePairingCode,
          profiles: Self.profiles,
          candidate: Self.candidate,
          displayName: "Custodian",
          platform: "iOS",
          vault: RappDeviceVault(accessGroup: nil),
          transport: transport))
    }

    /// A requester bridge keyed on `code`, ready to send Y_A.
    private func makeRequesterBridge(code: String) throws -> RappPairingBridge {
      let bridge = try RappPairingBridge.codeOffer(
        role: .requester,
        pairingCode: code,
        profiles: Self.profiles,
        transports: [Self.candidate.binding],
        offerTtlMs: RappPairingCode.offerLifetimeMilliseconds,
        startedAtMonotonicMs: RappPlatformClock().monotonicMilliseconds())
      try bridge.beginCpace(
        candidateId: Self.candidateID,
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
      XCTAssertTrue(firstSnapshot.frames.isEmpty)
      XCTAssertEqual(firstSnapshot.closeCount, 1)

      let replacement = RecordingTransport()
      let replaced = await custodian.replaceTransport(replacement)
      XCTAssertTrue(replaced)
      await custodian.transportConnected()
      let requester = try makeRequesterBridge(code: fixturePairingCode)
      await custodian.receive(
        try requester.writeCpaceFrame(nowMonotonicMs: RappPlatformClock().monotonicMilliseconds()))
      let replacementSnapshot = await replacement.snapshot()
      XCTAssertEqual(replacementSnapshot.frames.count, 1)
      await custodian.close()
      collector.cancel()
    }

    internal func testThreeMisreadCodesLockTheOffer() async throws {
      let restored = expectation(description: "offer restored after each failed attempt")
      restored.expectedFulfillmentCount = 2
      let closed = expectation(description: "offer locked")
      let custodian = try makeCustodian(transport: RecordingTransport())
      let collector = collect(custodian, restored: restored, closed: closed)

      for attempt in 1...3 {
        let transport = RecordingTransport()
        if attempt > 1 {
          let replaced = await custodian.replaceTransport(transport)
          XCTAssertTrue(replaced)
        }
        await custodian.transportConnected()
        let requester = try makeRequesterBridge(code: misreadPairingCode)
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
