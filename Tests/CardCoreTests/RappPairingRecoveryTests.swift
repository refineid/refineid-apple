// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// The code the custodian fixtures here show.
private let fixturePairingCode = "246813"
/// A code one character away, typed by a requester who misread it.
private let misreadPairingCode = "246814"

#if canImport(RappEngine)
  import RappEngine

  @Suite(.serialized)
  internal final class RappPairingRecoveryTests {
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
    private static let profiles = rappCredentialProfiles()
    private static let cpaceRandomByteCount = 64
    /// Longer than the custodian's pre-authentication spacing (§3.3 item 6).
    private static let reconnectSpacingNanoseconds: UInt64 = 600_000_000
    /// More misread codes than any per-offer count would admit.
    private static let misreadAttempts = 4
    private static let busyRestorationCount = 2

    private func makeCustodian(
      transport: RecordingTransport
    ) async throws -> RappPairingCoordinator {
      try await RappPairingCoordinator.attachedCustodian(
        options: .init(
          code: fixturePairingCode,
          profiles: Self.profiles,
          transportProfiles: [Self.transportProfile],
          displayName: TestDisplayNames.custodian,
          platform: "iOS",
          vault: RappDeviceVault(
            accessGroup: nil, servicePrefix: "fi.refineid.test.recovery.\(UUID().uuidString)")),
        transport: transport)
    }

    /// A requester bridge keyed on `code` over the offer the custodian
    /// served as its first frame, ready to send Y_A.
    private func makeRequesterBridge(
      code: String, offer: RecordingTransport
    ) async throws -> RappPairingBridge {
      let served = await offer.snapshot().frames
      let encodedOffer = try #require(served.first)
      let bridge = try RappPairingBridge.bootstrapOffer(
        bootstrap: encodedOffer,
        transportProfile: Self.transportProfile,
        pairingCode: code,
        startedAtMonotonicMs: RappPlatformClock().monotonicMilliseconds())
      try bridge.beginCpace(
        candidateId: try #require(rappCandidateIdentifier(transportProfile: Self.transportProfile)),
        randomBytes64: Data(repeating: 0x11, count: Self.cpaceRandomByteCount),
        nowMonotonicMs: RappPlatformClock().monotonicMilliseconds())
      return bridge
    }

    private func collect(
      _ coordinator: RappPairingCoordinator,
      restored: TestEvent,
      closed: TestEvent? = nil
    ) -> Task<RappPairingCoordinator.CloseReason?, Never> {
      let events = coordinator.events
      return Task {
        for await event in events {
          switch event {
          case .offerRestored:
            restored.signal()

          case .closed(let reason):
            closed?.signal()
            return reason

          case .keyConfirmed, .paired, .peerIntroduced:
            continue
          }
        }
        return nil
      }
    }

    @Test
    internal func testCustodianKeepsItsOfferAfterAnInvalidFirstMessage() async throws {
      let restored = TestEvent(description: "offer restored")
      let firstTransport = RecordingTransport()
      let custodian = try await makeCustodian(transport: firstTransport)
      let collector = collect(custodian, restored: restored)
      defer { collector.cancel() }

      await custodian.transportConnected()
      await custodian.receive(Data(count: 32))
      await TestEvent.wait(for: [restored], timeout: 2)
      let firstSnapshot = await firstTransport.snapshot()
      #expect((firstSnapshot.frames.count) == (1))
      #expect((firstSnapshot.closeCount) == (1))

      try await Task.sleep(nanoseconds: Self.reconnectSpacingNanoseconds)
      let replacement = RecordingTransport()
      let replaced = await custodian.attach(replacement, transportProfile: Self.transportProfile)
      #expect((replaced))
      await custodian.transportConnected()
      let requester = try await makeRequesterBridge(code: fixturePairingCode, offer: replacement)
      await custodian.receive(
        try requester.writeCpaceFrame(nowMonotonicMs: RappPlatformClock().monotonicMilliseconds()))
      let replacementSnapshot = await replacement.snapshot()
      #expect((replacementSnapshot.frames.count) == (2))
      expectState(
        replacementSnapshot.frames.first == firstSnapshot.frames.first,
        sourceLocation: #_sourceLocation)
      await custodian.close()
      collector.cancel()
    }

    @Test
    internal func testCustodianServesTheOfferOnceItConnects() async throws {
      let transport = RecordingTransport()
      let custodian = try await makeCustodian(transport: transport)
      await custodian.transportConnected()
      let frames = await transport.snapshot().frames
      #expect((frames.count) == (1))
      let offer = try #require(frames.first)
      #expect(throws: Never.self) {
        try RappPairingBridge.bootstrapOffer(
          bootstrap: offer, transportProfile: Self.transportProfile,
          pairingCode: fixturePairingCode,
          startedAtMonotonicMs: RappPlatformClock().monotonicMilliseconds())
      }
      await custodian.close()
    }

    @Test
    internal func testASecondConnectionWithinTheSpacingIsAnsweredBusy() async throws {
      let restored = TestEvent(
        description: "offer restored after each connection",
        expectedCount: Self.busyRestorationCount)
      let first = RecordingTransport()
      let custodian = try await makeCustodian(transport: first)
      let collector = collect(custodian, restored: restored)
      defer { collector.cancel() }

      await custodian.transportConnected()
      await custodian.receive(Data(count: 32))
      let second = RecordingTransport()
      let replaced = await custodian.attach(second, transportProfile: Self.transportProfile)
      #expect((replaced))
      await custodian.transportConnected()

      let refused = await second.snapshot()
      #expect((refused.frames.count) == (1))
      #expect((refused.closeCount) == (1))
      let busy = try #require(refused.frames.first)
      let wait = try rappPairingBusyRetryAfterMs(busy)
      #expect((wait) > (0))
      #expect((wait) <= (RappPreAuthenticationLimiter.minimumSpacingMilliseconds))
      await TestEvent.wait(for: [restored], timeout: 2)
      await custodian.close()
      collector.cancel()
    }

    @Test
    internal func testMisreadCodesKeepTheOffer() async throws {
      let restored = TestEvent(
        description: "offer restored after each failed attempt", expectedCount: Self.misreadAttempts
      )
      let firstTransport = RecordingTransport()
      let custodian = try await makeCustodian(transport: firstTransport)
      let collector = collect(custodian, restored: restored)
      defer { collector.cancel() }

      for attempt in 1...Self.misreadAttempts {
        var transport = firstTransport
        if attempt > 1 {
          try await Task.sleep(nanoseconds: Self.reconnectSpacingNanoseconds)
          transport = RecordingTransport()
          let replaced = await custodian.attach(transport, transportProfile: Self.transportProfile)
          #expect((replaced))
        }
        await custodian.transportConnected()
        let requester = try await makeRequesterBridge(code: misreadPairingCode, offer: transport)
        await custodian.receive(
          try requester.writeCpaceFrame(
            nowMonotonicMs: RappPlatformClock().monotonicMilliseconds()))
        // The requester sees T_B fail and drops the link without sending T_A.
        await custodian.transportClosed()
      }

      await TestEvent.wait(for: [restored], timeout: 2)
      await custodian.close()
      let reason = await collector.value
      #expect((reason) == (.localRequest))
    }
  }
#endif
