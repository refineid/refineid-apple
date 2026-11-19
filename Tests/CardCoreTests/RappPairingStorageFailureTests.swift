// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// The code the custodian fixture here shows.
private let fixturePairingCode = "246813"

#if canImport(RappEngine)
  import RappEngine

  /// A custodian that stored its record and then hears nonsense instead of
  /// the peer's `pairing.stored` revokes the record (RAPP v26.11.8 §4.3
  /// item 4).
  @Suite(.serialized)
  internal final class RappPairingStorageFailureTests {
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

    /// How a ceremony that stopped at the custodian's storage step ended.
    private struct EndedCeremony {
      let reason: RappPairingCoordinator.CloseReason?
      let frames: [Data]
      let requester: RappPairingBridge
    }

    private static let transportProfile = rappStreamProfileName()
    private static let profiles = rappCredentialProfiles()

    private var now: UInt64 { RappPlatformClock().monotonicMilliseconds() }

    /// The frame the custodian sent last.
    private func lastFrame(_ transport: RecordingTransport, expecting count: Int) async throws
      -> Data
    {
      let frames = await transport.snapshot()
      #expect((frames.count) == (count))
      return try #require(frames.last)
    }

    /// Runs the ceremony as the requester until the custodian has stored
    /// its record and sent `pairing.stored`, and returns the requester's
    /// bridge.
    @discardableResult
    private func driveToStorage(
      _ custodian: RappPairingCoordinator, transport: RecordingTransport
    ) async throws -> RappPairingBridge {
      await custodian.transportConnected()
      let offer = try await lastFrame(transport, expecting: 1)
      let requester = try RappPairingBridge.bootstrapOffer(
        bootstrap: offer, transportProfile: Self.transportProfile,
        pairingCode: fixturePairingCode, startedAtMonotonicMs: now)
      try requester.beginCpace(
        candidateId: try #require(rappCandidateIdentifier(transportProfile: Self.transportProfile)),
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
        try requester.sendHello(
          displayName: TestDisplayNames.requester, platform: "macOS", nowMonotonicMs: now))
      let answered = await transport.snapshot()
      #expect((answered.count) == (5))
      _ = try requester.receiveHello(bytes: answered[3], nowMonotonicMs: now)
      let granted = try requester.receiveConfirmation(bytes: answered[4], nowMonotonicMs: now)
      await custodian.receive(
        try requester.sendConfirmation(grantedProfiles: granted, nowMonotonicMs: now))
      return requester
    }

    @Test
    internal func testNonsenseInsteadOfPeerStorageRevokesTheStoredRecord() async throws {
      let vault = RappDeviceVault(
        accessGroup: nil, servicePrefix: "fi.refineid.test.storage.\(UUID().uuidString)")
      defer { _ = try? vault.deleteServiceNamespace("fi.refineid.test.storage") }
      let transport = RecordingTransport()
      let custodian = try await RappPairingCoordinator.attachedCustodian(
        options: .init(
          code: fixturePairingCode,
          profiles: Self.profiles,
          transportProfiles: [Self.transportProfile],
          displayName: TestDisplayNames.custodian,
          platform: "iOS",
          vault: vault),
        transport: transport)
      let ended = TestEvent(description: "the attempt ended")
      let events = custodian.events
      let collector = Task {
        for await event in events {
          if case .paired = event { continue }
          if case .peerIntroduced = event { continue }
          ended.signal()
          return
        }
      }
      defer { collector.cancel() }

      try await driveToStorage(custodian, transport: transport)

      // The custodian has stored its record and told the peer.
      _ = try await lastFrame(transport, expecting: 6)
      let stored = try vault.activePairIDs()
      #expect((stored.count) == (1))
      let pairID = try #require(stored.first)

      await custodian.receive(Data("not a pairing.stored frame".utf8))
      await TestEvent.wait(for: [ended], timeout: 2)
      expectState({ try vault.activePairIDs().isEmpty }, sourceLocation: #_sourceLocation)
      expectState(
        { try vault.loadPair(pairID: pairID) == nil }, sourceLocation: #_sourceLocation)
      await custodian.close()
    }

    /// A custodian whose keychain refuses the record confirms nothing,
    /// keeps nothing and reports the keychain's status.
    ///
    /// RAPP v26.11.8 §4.3 item 4.
    @Test
    internal func testARefusedWriteAbortsInsteadOfConfirming() async throws {
      for status in [errSecAuthFailed, errSecMissingEntitlement, errSecIO] {
        let vault = RappDeviceVault(
          accessGroup: nil, servicePrefix: "fi.refineid.test.storage.\(UUID().uuidString)")
        vault.testKeychain.refusal = { $0 == .add ? status : nil }
        let ended = try await runCeremony(vault: vault)

        #expect((ended.reason) == (.persistenceFailure(status: status)))
        expectState({ try vault.activePairIDs().isEmpty }, sourceLocation: #_sourceLocation)
        // The sixth frame is the abort: no `pairing.stored` was sent, and
        // the requester's storage exchange refuses it as a confirmation.
        #expect((ended.frames.count) == (6))
        _ = try ended.requester.buildPairRecord(createdAtMs: 0, nowMonotonicMs: now)
        #expect(throws: (any Error).self) {
          try ended.requester.receiveStored(bytes: ended.frames[5], nowMonotonicMs: now)
        }
      }
    }

    /// A disk full stays its own reason, and a refused write leaves no
    /// record behind.
    @Test
    internal func testAFullKeychainEndsOutOfSpace() async throws {
      let vault = RappDeviceVault(
        accessGroup: nil, servicePrefix: "fi.refineid.test.storage.\(UUID().uuidString)")
      vault.testKeychain.refusal = { $0 == .add ? errSecDiskFull : nil }
      let ended = try await runCeremony(vault: vault)
      #expect((ended.reason) == (.outOfSpace))
      expectState({ try vault.activePairIDs().isEmpty }, sourceLocation: #_sourceLocation)
    }

    /// A keychain that takes the record lets the ceremony confirm it.
    @Test
    internal func testAStoredWriteConfirms() async throws {
      let vault = RappDeviceVault(
        accessGroup: nil, servicePrefix: "fi.refineid.test.storage.\(UUID().uuidString)")
      let transport = RecordingTransport()
      let custodian = try await makeCustodian(vault: vault, transport: transport)
      try await driveToStorage(custodian, transport: transport)
      let frames = await transport.snapshot()
      #expect((frames.count) == (6))
      #expect((try vault.activePairIDs().count) == (1))
      await custodian.close()
    }

    /// Drives a ceremony to the custodian's storage step, and returns why
    /// the attempt ended, what it sent and the requester's bridge.
    private func runCeremony(vault: RappDeviceVault) async throws -> EndedCeremony {
      let transport = RecordingTransport()
      let custodian = try await makeCustodian(vault: vault, transport: transport)
      let events = custodian.events
      let collector = Task { () -> RappPairingCoordinator.CloseReason? in
        for await event in events {
          if case .closed(let reason) = event { return reason }
        }
        return nil
      }
      let requester = try await driveToStorage(custodian, transport: transport)
      let reason = await collector.value
      return EndedCeremony(
        reason: reason, frames: await transport.snapshot(), requester: requester)
    }

    private func makeCustodian(
      vault: RappDeviceVault, transport: RecordingTransport
    ) async throws -> RappPairingCoordinator {
      try await RappPairingCoordinator.attachedCustodian(
        options: .init(
          code: fixturePairingCode,
          profiles: Self.profiles,
          transportProfiles: [Self.transportProfile],
          displayName: TestDisplayNames.custodian,
          platform: "iOS",
          vault: vault),
        transport: transport)
    }
  }
#endif
