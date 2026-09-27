// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(Network) && canImport(RappEngine)
  @testable import CardCore
  import Foundation
  import Network
  import RappEngine
  import Testing

  @Suite("RappLocalDiscoveryTests")
  internal struct RappLocalDiscoveryTests {
    private final class LockedBox<T>: @unchecked Sendable {
      private let lock = NSLock()
      private var value: T

      init(_ initial: T) {
        self.value = initial
      }

      func set(_ newValue: T) {
        lock.lock()
        value = newValue
        lock.unlock()
      }

      func get() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
      }
    }

    @Test("Advertises and discovers peer records over local network")
    internal func testLocalPeerDiscovery() async throws {
      let holderID = try makeIdentity(
        service: "fi.refineid.test.disc.holder.\(UUID().uuidString)",
        name: "iPhone 16",
        model: "iPhone16,1",
        seed: 0x31
      )

      let requesterID = try makeIdentity(
        service: "fi.refineid.test.disc.req.\(UUID().uuidString)",
        name: "MacBook Pro",
        model: "Mac15,3",
        seed: 0x42
      )

      let holderDiscovered = LockedBox<RappCloudDeviceRecord?>(nil)
      let requesterDiscovered = LockedBox<RappCloudDeviceRecord?>(nil)

      let holderDisc = RappLocalDiscovery(
        localIdentity: holderID,
        localRole: .holder,
        serviceType: "_refineid-tst._tcp",
        onDiscovered: { record in
          holderDiscovered.set(record)
        }
      )

      let requesterDisc = RappLocalDiscovery(
        localIdentity: requesterID,
        localRole: .requester,
        serviceType: "_refineid-tst._tcp",
        onDiscovered: { record in
          if record.deviceID == holderID.deviceID {
            requesterDiscovered.set(record)
          }
        }
      )

      holderDisc.start()
      requesterDisc.start()

      // Poll until discovery completes or timeout
      var discoveredRecord: RappCloudDeviceRecord?
      for _ in 0..<50 {
        if let rec = requesterDiscovered.get() {
          discoveredRecord = rec
          break
        }
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
      }

      holderDisc.cancel()
      requesterDisc.cancel()

      if let discoveredRecord {
        #expect(discoveredRecord.deviceID == holderID.deviceID)
        #expect(discoveredRecord.deviceName == "iPhone 16")
        #expect(discoveredRecord.role == .holder)
        #expect(discoveredRecord.staticPublicKey == holderID.publicKeyData)
      }
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
