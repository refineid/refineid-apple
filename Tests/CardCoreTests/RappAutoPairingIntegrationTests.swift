// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  @testable import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  @Suite("RappAutoPairingIntegrationTests", .serialized)
  internal struct RappAutoPairingIntegrationTests {
    @Test("Complete end-to-end zero-touch autopairing, Noise session handshake, and signing")
    internal func testAutoPairingAndEndToEndSessionCrossing() async throws {
      RappPairNames.forgetAll()
      defer { RappPairNames.forgetAll() }
      let storage = InMemoryCloudStorage()

      // 1. Initialize iPhone (Card Holder) & Mac (Requester)
      let phonePrefix = "fi.refineid.test.e2e.phone.\(UUID().uuidString)"
      let phoneID = try makeIdentity(
        service: "\(phonePrefix).identity", name: "iPhone", model: "iPhone16,1", seed: "e2e phone")
      let phoneVault = RappDeviceVault(accessGroup: nil, servicePrefix: phonePrefix)
      let phoneCoordinator = RappCloudSyncCoordinator(
        localIdentity: phoneID, localRole: .holder, cloudStorage: storage)
      await phoneCoordinator.publishLocalDevice()

      let macPrefix = "fi.refineid.test.e2e.mac.\(UUID().uuidString)"
      let macID = try makeIdentity(
        service: "\(macPrefix).identity", name: "Mac", model: "Mac15,3", seed: "e2e mac")
      let macVault = RappDeviceVault(accessGroup: nil, servicePrefix: macPrefix)
      let macCoordinator = RappCloudSyncCoordinator(
        localIdentity: macID, localRole: .requester, cloudStorage: storage)

      // 2. Reconcile both sides via iCloud sync
      let macPairs = try await macCoordinator.reconcileVault(vault: macVault)
      let phonePairs = try await phoneCoordinator.reconcileVault(vault: phoneVault)
      #expect(macPairs.count == 1)
      #expect(phonePairs.count == 1)
      #expect(macPairs[0].metadata().pairId == phonePairs[0].metadata().pairId)

      // 3. Establish live session over loopback wire and execute signature
      try await assertSessionAndSignature(
        requesterPair: macPairs[0],
        proxyPair: phonePairs[0],
        origin: "https://e2e.example.invalid"
      )
    }

    @Test("iPhone holder concurrently autopairs with both Mac and iPad requesters without PIN")
    internal func testMultiDeviceConcurrentAutoPairing() async throws {
      RappPairNames.forgetAll()
      defer { RappPairNames.forgetAll() }
      let storage = InMemoryCloudStorage()

      // 1. Initialize iPhone holder with primed identity
      let phonePrefix = "fi.refineid.test.multi.phone.\(UUID().uuidString)"
      let phoneID = try makeIdentity(
        service: "\(phonePrefix).identity", name: "Alpha iPhone", model: "iPhone16,1",
        seed: "multi phone")
      let phoneVault = RappDeviceVault(accessGroup: nil, servicePrefix: phonePrefix)
      let phoneCoordinator = RappCloudSyncCoordinator(
        localIdentity: phoneID, localRole: .holder, cloudStorage: storage)
      await phoneCoordinator.publishLocalDevice()

      // 2. Initialize Mac requester
      let macPrefix = "fi.refineid.test.multi.mac.\(UUID().uuidString)"
      let macID = try makeIdentity(
        service: "\(macPrefix).identity", name: "Alpha Mac", model: "Mac15,3", seed: "multi mac")
      let macVault = RappDeviceVault(accessGroup: nil, servicePrefix: macPrefix)
      let macCoordinator = RappCloudSyncCoordinator(
        localIdentity: macID, localRole: .requester, cloudStorage: storage)
      await macCoordinator.publishLocalDevice()

      // 3. Initialize iPad requester
      let ipadPrefix = "fi.refineid.test.multi.ipad.\(UUID().uuidString)"
      let ipadID = try makeIdentity(
        service: "\(ipadPrefix).identity", name: "Alpha iPad", model: "iPad14,3", seed: "multi ipad"
      )
      let ipadVault = RappDeviceVault(accessGroup: nil, servicePrefix: ipadPrefix)
      let ipadCoordinator = RappCloudSyncCoordinator(
        localIdentity: ipadID, localRole: .requester, cloudStorage: storage)
      await ipadCoordinator.publishLocalDevice()

      // 4. Reconcile all three devices
      let phonePairs = try await phoneCoordinator.reconcileVault(vault: phoneVault)
      let macPairs = try await macCoordinator.reconcileVault(vault: macVault)
      let ipadPairs = try await ipadCoordinator.reconcileVault(vault: ipadVault)

      // iPhone paired with both Mac and iPad
      #expect(phonePairs.count == 2)
      // Mac paired with iPhone
      #expect(macPairs.count == 1)
      // iPad paired with iPhone
      #expect(ipadPairs.count == 1)

      #expect(RappPairNames.name(forPairID: macPairs[0].metadata().pairId) == "Alpha iPhone")
      #expect(RappPairNames.name(forPairID: ipadPairs[0].metadata().pairId) == "Alpha iPhone")

      // Both Mac and iPad have the pair selected
      #expect(try macVault.selectedPairID() == macPairs[0].metadata().pairId)
      #expect(try ipadVault.selectedPairID() == ipadPairs[0].metadata().pairId)
    }

    @Test("Resetting a pair immediately auto-repairs with the primed holder and verifies session")
    internal func testResetPairReAutoPairsAndEstablishesSession() async throws {
      RappPairNames.forgetAll()
      defer { RappPairNames.forgetAll() }
      let storage = InMemoryCloudStorage()

      // 1. Initialize iPhone holder and Mac requester
      let phonePrefix = "fi.refineid.test.reset.phone.\(UUID().uuidString)"
      let phoneID = try makeIdentity(
        service: "\(phonePrefix).identity", name: "iPhone", model: "iPhone16,1", seed: "reset phone"
      )
      let phoneVault = RappDeviceVault(accessGroup: nil, servicePrefix: phonePrefix)
      let phoneCoordinator = RappCloudSyncCoordinator(
        localIdentity: phoneID, localRole: .holder, cloudStorage: storage)
      await phoneCoordinator.publishLocalDevice()

      let macPrefix = "fi.refineid.test.reset.mac.\(UUID().uuidString)"
      let macID = try makeIdentity(
        service: "\(macPrefix).identity", name: "Mac", model: "Mac15,3", seed: "reset mac")
      let macVault = RappDeviceVault(accessGroup: nil, servicePrefix: macPrefix)
      let macCoordinator = RappCloudSyncCoordinator(
        localIdentity: macID, localRole: .requester, cloudStorage: storage)

      // 2. Initial reconcile establishes the pair on both sides
      let initialMacPairs = try await macCoordinator.reconcileVault(vault: macVault)
      let initialPhonePairs = try await phoneCoordinator.reconcileVault(vault: phoneVault)
      #expect(initialMacPairs.count == 1)
      #expect(initialPhonePairs.count == 1)
      let pairID = initialMacPairs[0].metadata().pairId
      #expect(pairID == initialPhonePairs[0].metadata().pairId)
      #expect(try macVault.selectedPairID() == pairID)

      // 3. User hits minus / resets pairing on Mac
      try RappPairRevocation.revoke(pairID: pairID, in: macVault, clock: RappPlatformClock())
      #expect(try macVault.activePairIDs().isEmpty)
      #expect(try macVault.loadPair(pairID: pairID) == nil)
      #expect(try macVault.pairIsRevoked(pairID: pairID) == false)
      #expect(try macVault.selectedPairID() == nil)

      // 4. Reconcile automatically recreates the pair and auto-selects it
      let repairedMacPairs = try await macCoordinator.reconcileVault(vault: macVault)
      #expect(repairedMacPairs.count == 1)
      #expect(repairedMacPairs[0].metadata().pairId == pairID)
      #expect(try macVault.selectedPairID() == pairID)
      #expect(try macVault.activePairIDs() == [pairID])

      // 5. Establish live session to prove end-to-end cryptographic and operational validity
      try await assertSessionAndSignature(
        requesterPair: repairedMacPairs[0],
        proxyPair: initialPhonePairs[0],
        origin: "https://reset.example.invalid"
      )
    }

    /// Opens a session over the two halves of the pairing and signs one
    /// challenge through it.
    private func assertSessionAndSignature(
      requesterPair: RappPairRecord,
      proxyPair: RappPairRecord,
      origin: String
    ) async throws {
      let connection = try await RappIntegrationConnectionSupport.makeConnection(
        requesterPair: requesterPair, proxyPair: proxyPair)
      let operation = RappIntegrationFixtures.RequestedOperation.browserAuthentication(
        origin: origin)
      let requesterOutcome = Task {
        try await RappIntegrationConnectionSupport.awaitCompletion(
          connection.requester, operation: operation)
      }
      let proxyOutcome = Task {
        try await RappIntegrationAuthorizationSupport.authorizeAndComplete(
          connection.proxy, operation: operation, signature: RappIntegrationFixtures.signature)
      }
      defer {
        requesterOutcome.cancel()
        proxyOutcome.cancel()
      }

      await connection.proxy.start()
      await connection.requester.start()
      #expect(try await requesterOutcome.value == .signature(RappIntegrationFixtures.signature))
      _ = try await proxyOutcome.value
      await connection.requester.close()
      await connection.proxy.close()
    }

    /// An identity whose fixed key derives from `seed`, so each simulated
    /// device keeps its own.
    private func makeIdentity(service: String, name: String, model: String, seed: String) throws
      -> RappDeviceIdentity
    {
      try RappDeviceIdentity(
        accessGroup: nil,
        service: service,
        deviceName: name,
        modelName: model,
        fixedPrivateKey: Data(SHA256.hash(data: Data(seed.utf8))),
        fixedDeviceID: UUID()
      )
    }
  }
#endif
