// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Coordinates zero-touch device pairing across devices sharing the same Apple ID.
  ///
  /// Periodically or upon change notifications, this coordinator syncs device public keys
  /// through iCloud Key-Value storage and reconciles them into the local `RappDeviceVault`.
  public actor RappCloudSyncCoordinator {
    // MARK: Constants

    private enum Constants {
      /// Maximum record age (30 days in seconds).
      static let maxRecordAgeSeconds: TimeInterval = 2_592_000
    }

    /// The key in `NSUbiquitousKeyValueStore` holding all registered device records.
    public static let cloudDevicesKey = "fi.refineid.rapp.cloud_devices"

    // MARK: Properties

    /// The persistent cryptographic identity of the local device.
    public let localIdentity: RappDeviceIdentity
    /// The operational role of the local device.
    public let localRole: RappDeviceRole
    private let cloudStorage: any RappCloudStorage
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var inMemoryDirectory: [UUID: RappCloudDeviceRecord] = [:]

    // MARK: Initialization

    /// Creates a coordinator for synchronizing same-account devices.
    public init(
      localIdentity: RappDeviceIdentity,
      localRole: RappDeviceRole,
      cloudStorage: any RappCloudStorage = UbiquitousKeyValueStoreCloudStorage()
    ) {
      self.localIdentity = localIdentity
      self.localRole = localRole
      self.cloudStorage = cloudStorage
      self.encoder = JSONEncoder()
      self.encoder.dateEncodingStrategy = .iso8601
      self.decoder = JSONDecoder()
      self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: Public API

    /// Publishes this device's current public record into the iCloud directory.
    @discardableResult
    public func publishLocalDevice() -> RappCloudDeviceRecord {
      let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
      let record = RappCloudDeviceRecord(
        deviceID: localIdentity.deviceID,
        deviceName: localIdentity.deviceName,
        modelName: localIdentity.modelName,
        role: localRole,
        staticPublicKey: localIdentity.publicKeyData,
        updatedAt: Date(),
        appBuildVersion: appVersion
      )

      #if targetEnvironment(simulator)
        if cloudStorage is UbiquitousKeyValueStoreCloudStorage {
          return record
        }
      #endif

      var directory = loadDirectory()
      // Purge any stale ghost records matching this device's name
      directory = directory.filter { _, existing in
        !(existing.deviceName.caseInsensitiveCompare(localIdentity.deviceName) == .orderedSame
          && existing.deviceID != localIdentity.deviceID)
      }
      directory[localIdentity.deviceID] = record
      saveDirectory(directory)
      return record
    }

    /// Removes this device from the iCloud directory (e.g. on sign out or app reset).
    public func unpublishLocalDevice() {
      var directory = loadDirectory()
      directory.removeValue(forKey: localIdentity.deviceID)
      saveDirectory(directory)
    }

    /// Removes a specific remote device from the iCloud directory.
    public func removeRemoteDevice(deviceID: UUID) {
      var directory = loadDirectory()
      let targetRecord = directory[deviceID] ?? inMemoryDirectory[deviceID]
      let targetKey = targetRecord?.staticPublicKey
      let targetName = targetRecord?.deviceName.lowercased()

      directory = directory.filter { key, record in
        if key == deviceID { return false }
        if let targetKey, record.staticPublicKey == targetKey { return false }
        if let targetName, record.deviceName.lowercased() == targetName { return false }
        return true
      }
      inMemoryDirectory = inMemoryDirectory.filter { key, record in
        if key == deviceID { return false }
        if let targetKey, record.staticPublicKey == targetKey { return false }
        if let targetName, record.deviceName.lowercased() == targetName { return false }
        return true
      }
      saveDirectory(directory)
    }

    /// Clears all remote devices from the iCloud directory, keeping only the local device.
    public func clearAllRemoteDevices() {
      var directory = loadDirectory()
      directory = directory.filter { $0.key == localIdentity.deviceID }
      inMemoryDirectory = inMemoryDirectory.filter { $0.key == localIdentity.deviceID }
      saveDirectory(directory)
    }

    /// Registers a locally discovered or received remote device record.
    public func registerDiscoveredDevice(_ record: RappCloudDeviceRecord) {
      guard record.deviceID != localIdentity.deviceID,
        record.deviceName.caseInsensitiveCompare(localIdentity.deviceName) != .orderedSame
      else { return }
      inMemoryDirectory[record.deviceID] = record
      var directory = loadDirectory()
      directory[record.deviceID] = record
      saveDirectory(directory)
    }

    /// Fetches all remote devices currently registered in iCloud.
    public func remoteDevices() -> [RappCloudDeviceRecord] {
      let directory = loadDirectory()
      let thirtyDaysAgo = Date().addingTimeInterval(-Constants.maxRecordAgeSeconds)

      let validRecords = directory.values.filter { record in
        record.deviceID != localIdentity.deviceID
          && record.deviceName.caseInsensitiveCompare(localIdentity.deviceName) != .orderedSame
          && record.updatedAt >= thirtyDaysAgo
      }

      // Deduplicate by static public key first, picking the most recently updated entry
      var byKey: [Data: RappCloudDeviceRecord] = [:]
      for record in validRecords.sorted(by: { $0.updatedAt < $1.updatedAt }) {
        byKey[record.staticPublicKey] = record
      }

      // Deduplicate by lowercased device name, picking the most recently updated entry
      var byName: [String: RappCloudDeviceRecord] = [:]
      for record in byKey.values.sorted(by: { $0.updatedAt < $1.updatedAt }) {
        byName[record.deviceName.lowercased()] = record
      }

      return Array(byName.values).sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Reconciles the cloud directory against the local device vault.
    ///
    /// Any compatible peer (e.g. an iPhone holder when we are a Mac/iPad requester)
    /// is automatically instantiated as a `RappPairRecord` and stored in `RappDeviceVault`.
    ///
    /// - Returns: The list of established/active same-account pairs.
    @discardableResult
    public func reconcileVault(vault: RappDeviceVault) throws -> [RappPairRecord] {
      // 1. Ensure local device is published
      publishLocalDevice()

      let remotes = remoteDevices()
      var establishedPairs: [RappPairRecord] = []

      for remote in remotes {
        // Pair with peers of the complementary role (or all peers if applicable)
        let isComplementary =
          (localRole == .requester && remote.role == .holder)
          || (localRole == .holder && remote.role == .requester)

        guard isComplementary else { continue }

        let pairID = RappSameAccountPairBuilder.derivePairIdentifier(
          publicKeyA: localIdentity.publicKeyData,
          publicKeyB: remote.staticPublicKey
        )

        let existingRecordData = try vault.loadPair(pairID: pairID)
        let pair: RappPairRecord
        if let existingRecordData {
          pair = try RappPairRecord.decode(from: existingRecordData)
        } else {
          let endpointRole: RappEndpointRole = (localRole == .requester) ? .requester : .proxy
          pair = try RappSameAccountPairBuilder.makePairRecord(
            localStaticPrivate: localIdentity.privateKeyData,
            localStaticPublic: localIdentity.publicKeyData,
            localRole: endpointRole,
            remotePublicKey: remote.staticPublicKey
          )
          try pair.persistDeviceOnly(vault: vault)
        }

        establishedPairs.append(pair)
        RappPairNames.remember(remote.deviceName, pairID: pairID)
        RappPairNames.rememberModel(remote.modelName, pairID: pairID)

      }

      let currentSelected = try vault.selectedPairID()
      let activeIDs = Set(try vault.activePairIDs())
      let isStale = currentSelected.map { !activeIDs.contains($0) } ?? true
      if let first = establishedPairs.first, isStale {
        try vault.selectPair(pairID: first.metadata().pairId)
      }

      return establishedPairs
    }

    // MARK: Private Helpers

    private func loadDirectory() -> [UUID: RappCloudDeviceRecord] {
      var result = inMemoryDirectory
      if let data = cloudStorage.data(forKey: Self.cloudDevicesKey) {
        if let stringKeyed = try? decoder.decode([String: RappCloudDeviceRecord].self, from: data) {
          for (key, record) in stringKeyed {
            if let uuid = UUID(uuidString: key) {
              result[uuid] = record
            }
          }
        } else if let uuidKeyed = try? decoder.decode(
          [UUID: RappCloudDeviceRecord].self, from: data)
        {
          for (key, record) in uuidKeyed {
            result[key] = record
          }
        }
      }
      return result
    }

    private func saveDirectory(_ directory: [UUID: RappCloudDeviceRecord]) {
      inMemoryDirectory = directory
      var stringKeyed: [String: RappCloudDeviceRecord] = [:]
      for (key, record) in directory {
        stringKeyed[key.uuidString] = record
      }
      guard let data = try? encoder.encode(stringKeyed) else { return }
      cloudStorage.set(data, forKey: Self.cloudDevicesKey)
      _ = cloudStorage.synchronize()
    }
  }
#endif
