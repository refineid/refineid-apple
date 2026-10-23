// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  @testable import CardCore
  import Foundation
  import RappEngine
  import Testing

  @Suite("RappCloudSyncCoordinatorTests")
  internal struct RappCloudSyncCoordinatorTests {
    @Test("Publishes local device and retrieves remote devices correctly")
    internal func testPublishAndRetrieve() async throws {
      let runID = UUID().uuidString
      let storage = InMemoryCloudStorage()

      let identityA = try makeIdentity(
        service: "fi.refineid.test.idA.\(runID)",
        name: "Alpha iPhone",
        model: "iPhone16,1",
        seed: 0x01
      )
      let coordinatorA = RappCloudSyncCoordinator(
        localIdentity: identityA,
        localRole: .holder,
        cloudStorage: storage
      )

      let recordA = await coordinatorA.publishLocalDevice()
      #expect(recordA.deviceID == identityA.deviceID)
      #expect(recordA.role == .holder)
      #expect(await coordinatorA.remoteDevices().isEmpty)

      let identityB = try makeIdentity(
        service: "fi.refineid.test.idB.\(runID)",
        name: "Alpha MacBook Pro",
        model: "Mac15,3",
        seed: 0x02
      )
      let coordinatorB = RappCloudSyncCoordinator(
        localIdentity: identityB,
        localRole: .requester,
        cloudStorage: storage
      )

      await coordinatorB.publishLocalDevice()

      let remotesForA = await coordinatorA.remoteDevices()
      #expect(remotesForA.count == 1)
      #expect(remotesForA.first?.deviceName == "Alpha MacBook Pro")
      #expect(remotesForA.first?.role == .requester)

      let remotesForB = await coordinatorB.remoteDevices()
      #expect(remotesForB.count == 1)
      #expect(remotesForB.first?.deviceName == "Alpha iPhone")
      #expect(remotesForB.first?.role == .holder)
    }

    @Test("A requester removes every phone it pairs with from the directory, and nothing else")
    internal func removesComplementaryDevices() async throws {
      let runID = UUID().uuidString
      let storage = InMemoryCloudStorage()
      let phone = RappCloudSyncCoordinator(
        localIdentity: try makeIdentity(
          service: "fi.refineid.test.phone.\(runID)", name: "Alpha iPhone", model: "iPhone16,1",
          seed: 0x01),
        localRole: .holder, cloudStorage: storage)
      let tablet = RappCloudSyncCoordinator(
        localIdentity: try makeIdentity(
          service: "fi.refineid.test.tablet.\(runID)", name: "Alpha iPad", model: "iPad14,1",
          seed: 0x03),
        localRole: .requester, cloudStorage: storage)
      let computer = RappCloudSyncCoordinator(
        localIdentity: try makeIdentity(
          service: "fi.refineid.test.computer.\(runID)", name: "Alpha MacBook Pro",
          model: "Mac15,3", seed: 0x02),
        localRole: .requester, cloudStorage: storage)
      await phone.publishLocalDevice()
      await tablet.publishLocalDevice()
      await computer.publishLocalDevice()

      #expect(await computer.removeComplementaryDevices() == 1)
      let left = await computer.remoteDevices()
      #expect(left.map(\.role) == [.requester], "only the phone goes")
      #expect(await computer.removeComplementaryDevices() == 0)
    }

    @Test("Reconciles 1:N multi-device topology across iPhone, Mac, and iPad")
    internal func testMultiDeviceReconciliation() async throws {
      let runID = UUID().uuidString
      let storage = InMemoryCloudStorage()

      let phoneID = try makeIdentity(
        service: "fi.refineid.test.phone.\(runID)", name: "iPhone", model: "iPhone16,1", seed: 0x11)
      let phoneVault = RappDeviceVault(
        accessGroup: nil, servicePrefix: "fi.refineid.test.vault.phone.\(runID)")
      let phoneCoord = RappCloudSyncCoordinator(
        localIdentity: phoneID, localRole: .holder, cloudStorage: storage)
      await phoneCoord.publishLocalDevice()

      let macID = try makeIdentity(
        service: "fi.refineid.test.mac.\(runID)", name: "Mac", model: "Mac15,3", seed: 0x22)
      let macVault = RappDeviceVault(
        accessGroup: nil, servicePrefix: "fi.refineid.test.vault.mac.\(runID)")
      let macCoord = RappCloudSyncCoordinator(
        localIdentity: macID, localRole: .requester, cloudStorage: storage)

      let ipadID = try makeIdentity(
        service: "fi.refineid.test.ipad.\(runID)", name: "iPad", model: "iPad14,3", seed: 0x33)
      let ipadVault = RappDeviceVault(
        accessGroup: nil, servicePrefix: "fi.refineid.test.vault.ipad.\(runID)")
      let ipadCoord = RappCloudSyncCoordinator(
        localIdentity: ipadID, localRole: .requester, cloudStorage: storage)

      let macPairs = try await macCoord.reconcileVault(vault: macVault)
      #expect(macPairs.count == 1)
      #expect(try macVault.activePairIDs().count == 1)

      let ipadPairs = try await ipadCoord.reconcileVault(vault: ipadVault)
      #expect(ipadPairs.count == 1)
      #expect(try ipadVault.activePairIDs().count == 1)

      let phonePairs = try await phoneCoord.reconcileVault(vault: phoneVault)
      #expect(phonePairs.count == 2)
      #expect(try phoneVault.activePairIDs().count == 2)
    }

    @Test("Deleting a pair lets reconcile recreate it from the same-account directory")
    internal func testResetPairRecreatesOnReconcile() async throws {
      let runID = UUID().uuidString
      let storage = InMemoryCloudStorage()

      let phoneID = try makeIdentity(
        service: "fi.refineid.test.rev.phone.\(runID)", name: "iPhone", model: "iPhone", seed: 0x55)
      let phoneCoord = RappCloudSyncCoordinator(
        localIdentity: phoneID, localRole: .holder, cloudStorage: storage)
      await phoneCoord.publishLocalDevice()

      let macID = try makeIdentity(
        service: "fi.refineid.test.rev.mac.\(runID)", name: "Mac", model: "Mac", seed: 0x66)
      let macVault = RappDeviceVault(
        accessGroup: nil, servicePrefix: "fi.refineid.test.vault.rev.mac.\(runID)")
      let macCoord = RappCloudSyncCoordinator(
        localIdentity: macID, localRole: .requester, cloudStorage: storage)

      let pairs = try await macCoord.reconcileVault(vault: macVault)
      #expect(pairs.count == 1)
      let pairID = pairs[0].metadata().pairId

      try macVault.revokePair(pairID: pairID, revokedAtMilliseconds: 2_000_000)
      #expect(try macVault.activePairIDs().isEmpty)
      #expect(try macVault.pairIsRevoked(pairID: pairID) == false)

      let subsequentPairs = try await macCoord.reconcileVault(vault: macVault)
      #expect(subsequentPairs.count == 1)
      #expect(try macVault.activePairIDs().count == 1)
      #expect(subsequentPairs[0].metadata().pairId == pairID)
    }

    private func makeIdentity(service: String, name: String, model: String, seed: UInt8) throws
      -> RappDeviceIdentity
    {
      try RappDeviceIdentity(
        accessGroup: nil,
        service: service,
        deviceName: name,
        modelName: model,
        fixedPrivateKey: Data(repeating: seed, count: 32),
        fixedDeviceID: UUID()
      )
    }
  }
#endif
