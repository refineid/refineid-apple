// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import XCTest

@testable import CardCore

/// The six-digit code the two fixtures here key their CPace PAKE on.
private let fixturePairingCode = "246813"

#if canImport(RappEngine)
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

      func snapshot() -> (frameCount: Int, closeCount: Int) {
        (frames.count, closes)
      }
    }

    private func makeRequester(
      transport: RecordingTransport
    ) throws -> RappPairingCoordinator {
      try RappPairingCoordinator.requester(
        profiles: ["fi.refineid.authentication.v1"],
        candidates: [
          .init(
            profile: "local-quic-v1",
            candidateID: "candidate",
            parametersCBOR: Data([0xa0])
          )
        ],
        selectedCandidateID: "candidate",
        offerLifetimeMilliseconds: 60_000,
        displayName: "Requester",
        platform: "macOS",
        vault: RappDeviceVault(accessGroup: nil),
        transport: transport,
        code: fixturePairingCode
      )
    }

    internal func testRequesterReusesOfferWithFreshTransportAfterHandshakeGarbage() async throws {
      let initialOffer = expectation(description: "initial offer")
      let restoredOffer = expectation(description: "restored offer")
      let firstTransport = RecordingTransport()
      let coordinator = try makeRequester(transport: firstTransport)
      let events = coordinator.events
      let collector = Task { () -> (String, String)? in
        var published: String?
        for await event in events {
          switch event {
          case .offerReady(let uri):
            published = uri
            initialOffer.fulfill()

          case .offerRestored(let uri):
            restoredOffer.fulfill()
            return published.map { ($0, uri) }

          case .reviewPeer, .paired, .closed:
            continue
          }
        }
        return nil
      }

      await coordinator.publishOffer()
      await fulfillment(of: [initialOffer], timeout: 2)
      await coordinator.transportConnected()
      let firstConnectedSnapshot = await firstTransport.snapshot()
      XCTAssertEqual(firstConnectedSnapshot.frameCount, 1)

      await coordinator.receive(Data())
      await fulfillment(of: [restoredOffer], timeout: 2)
      let collectedOffers = await collector.value
      let offers = try XCTUnwrap(collectedOffers)
      XCTAssertEqual(offers.0, offers.1)
      let firstFailedSnapshot = await firstTransport.snapshot()
      XCTAssertEqual(firstFailedSnapshot.closeCount, 1)

      let replacement = RecordingTransport()
      let replaced = await coordinator.replaceTransport(replacement)
      XCTAssertTrue(replaced)
      await coordinator.transportConnected()
      let replacementSnapshot = await replacement.snapshot()
      XCTAssertEqual(replacementSnapshot.frameCount, 1)
      await coordinator.close()
    }
  }
#endif
