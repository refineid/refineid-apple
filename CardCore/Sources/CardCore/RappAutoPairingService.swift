// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Service managing automatic same-account device pairing and iCloud background synchronization.
  public final class RappAutoPairingService: @unchecked Sendable {
    // MARK: Static Properties

    /// The shared service instance.
    public static let shared = RappAutoPairingService()

    /// Posted when the set of active pairings changes.
    public static let pairingsDidChangeNotification = Notification.Name(
      "fi.refineid.pairingsDidChange"
    )

    /// Posted after each reconcile of the account's device directory.
    public static let devicesDidChangeNotification = Notification.Name(
      "fi.refineid.devicesDidChange"
    )

    // MARK: Properties

    private var coordinator: RappCloudSyncCoordinator?
    private var externalChangeObserver: (any NSObjectProtocol)?
    private let lock = NSLock()
    private var isStarted = false
    private var cachedRemoteDevices: [RappCloudDeviceRecord] = []

    /// List of discovered remote devices from the same Apple Account.
    public var remoteDevices: [RappCloudDeviceRecord] {
      lock.lock()
      defer { lock.unlock() }
      return cachedRemoteDevices
    }

    /// The local device's operational role.
    public var localRole: RappDeviceRole? {
      coordinator?.localRole
    }

    /// The persistent cryptographic identity of the local device.
    public var localIdentity: RappDeviceIdentity? {
      coordinator?.localIdentity
    }

    // MARK: Initialization

    private init() {
      // Singleton instance initialization
    }

    // MARK: Public API

    /// Starts iCloud synchronization and listens for external device updates.
    public func start() {
      lock.lock()
      defer { lock.unlock() }

      guard !isStarted else { return }
      isStarted = true

      guard let identity = try? RappDeviceIdentity() else { return }
      let role: RappDeviceRole
      #if os(iOS)
        if SupportedCardTransports.offersNearField {
          role = .holder
        } else {
          role = .requester
        }
      #else
        role = .requester
      #endif

      let syncCoordinator = RappCloudSyncCoordinator(
        localIdentity: identity,
        localRole: role
      )
      self.coordinator = syncCoordinator

      // 1. Initial reconciliation
      Task { [weak self] in
        self?.reconcile()
      }

      // 2. Observe iCloud external changes
      externalChangeObserver = NotificationCenter.default.addObserver(
        forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
        object: NSUbiquitousKeyValueStore.default,
        queue: .main
      ) { [weak self] _ in
        Task { [weak self] in
          self?.reconcile()
        }
      }
    }

    /// Triggers an immediate reconciliation of the cloud directory against the local device vault.
    public func reconcile() {
      guard let coordinator else { return }
      let vault = RappDeviceVault()
      Task {
        let pairsBefore = RappPairingSnapshot(vault: vault)
        // Remote access is opt-in: while the holder has it off, nothing
        // may re-enter the vault, or turning it off would not hold.
        #if os(iOS)
          if RemoteAccessGate.isEnabled {
            _ = (try? await coordinator.reconcileVault(vault: vault)) ?? []
          }
        #else
          _ = (try? await coordinator.reconcileVault(vault: vault)) ?? []
        #endif
        let remotes = await coordinator.remoteDevices()
        self.updateCachedRemoteDevices(remotes)
        let pairsChanged = pairsBefore.differs(from: RappPairingSnapshot(vault: vault))
        await MainActor.run {
          let center = NotificationCenter.default
          if pairsChanged { center.post(name: Self.pairingsDidChangeNotification, object: nil) }
          center.post(name: Self.devicesDidChangeNotification, object: nil)
        }
      }
    }

    /// Removes a specific remote device from cloud synchronization and reconciles.
    public func removeRemoteDevice(deviceID: UUID) {
      guard let coordinator else { return }
      Task {
        await coordinator.removeRemoteDevice(deviceID: deviceID)
        let remotes = await coordinator.remoteDevices()
        self.updateCachedRemoteDevices(remotes)
        reconcile()
      }
    }

    /// Clears all remote devices from cloud synchronization and reconciles.
    public func clearAllRemoteDevices() {
      guard let coordinator else { return }
      Task {
        await coordinator.clearAllRemoteDevices()
        reconcile()
      }
    }

    private func updateCachedRemoteDevices(_ remotes: [RappCloudDeviceRecord]) {
      lock.lock()
      cachedRemoteDevices = remotes
      lock.unlock()
    }

    deinit {
      if let observer = externalChangeObserver {
        NotificationCenter.default.removeObserver(observer)
      }
    }
  }
#endif
