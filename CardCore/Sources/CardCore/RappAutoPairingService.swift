// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Service managing automatic same-account device pairing and iCloud background synchronization.
  public final class RappAutoPairingService: @unchecked Sendable {
    // MARK: Static Properties

    /// The shared service instance.
    public static let shared = RappAutoPairingService()

    /// Posted when same-account auto-pairing reconciles or active pairings change.
    public static let pairingsDidChangeNotification = Notification.Name(
      "fi.refineid.pairingsDidChange"
    )

    // MARK: Properties

    private var coordinator: RappCloudSyncCoordinator?
    private var externalChangeObserver: (any NSObjectProtocol)?
    #if canImport(Network)
      private var localDiscovery: RappLocalDiscovery?
    #endif
    private let lock = NSLock()
    private var isStarted = false
    private var cachedRemoteDevices: [RappCloudDeviceRecord] = []
    private var liveOnlineDeviceIDs = Set<UUID>()
    private var liveOnlineDeviceNames = Set<String>()

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

    /// Whether any remote holder device is known from iCloud synchronization or established pairings.
    public var hasKnownRemoteHolders: Bool {
      let remotes = remoteDevices.filter { record in
        record.role == .holder
      }
      if !remotes.isEmpty { return true }
      let pairs = (try? RappDeviceVault().activePairIDs()) ?? []
      return !pairs.isEmpty
    }

    /// Checks whether any paired peer device (or known remote requester/holder) is online.
    public var isAnyPairedPeerOnline: Bool {
      lock.lock()
      defer { lock.unlock() }
      for device in cachedRemoteDevices {
        if liveOnlineDeviceIDs.contains(device.deviceID) {
          return true
        }
        let lower = device.deviceName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = lower.replacingOccurrences(of: ".local", with: "")
        if !lower.isEmpty,
          liveOnlineDeviceNames.contains(lower) || liveOnlineDeviceNames.contains(stripped)
        {
          return true
        }
      }
      if let activeIDs = try? RappDeviceVault().activePairIDs(), !activeIDs.isEmpty {
        for pairID in activeIDs {
          if let name = RappPairNames.name(forPairID: pairID) {
            let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let stripped = lower.replacingOccurrences(of: ".local", with: "")
            if !lower.isEmpty,
              liveOnlineDeviceNames.contains(lower) || liveOnlineDeviceNames.contains(stripped)
            {
              return true
            }
          }
        }
        if !liveOnlineDeviceIDs.isEmpty || !liveOnlineDeviceNames.isEmpty {
          return true
        }
      }
      return false
    }

    // MARK: Initialization

    private init() {
      // Singleton instance initialization
    }

    // MARK: Public API

    /// Checks whether a remote device is currently discovered and reachable on the local network.
    public func isDeviceOnline(deviceID: UUID?, deviceName: String?) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      if let deviceID, liveOnlineDeviceIDs.contains(deviceID) {
        return true
      }
      guard let deviceName else { return false }
      let lower = deviceName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
      guard !lower.isEmpty else { return false }
      if liveOnlineDeviceNames.contains(lower) {
        return true
      }
      let stripped = lower.replacingOccurrences(of: ".local", with: "")
      if liveOnlineDeviceNames.contains(stripped) {
        return true
      }
      return false
    }

    /// Updates the set of live online devices discovered over Bonjour.
    public func updateOnlineDevices(ids: Set<UUID>, names: Set<String>) {
      lock.lock()
      guard liveOnlineDeviceIDs != ids || liveOnlineDeviceNames != names else {
        lock.unlock()
        return
      }
      liveOnlineDeviceIDs = ids
      liveOnlineDeviceNames = names
      lock.unlock()
      Task { @MainActor in
        NotificationCenter.default.post(
          name: Self.pairingsDidChangeNotification,
          object: nil
        )
      }
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

      // 2. Start local network discovery (Bonjour / LAN)
      #if canImport(Network)
        #if os(iOS)
          if RemoteAccessGate.isEnabled {
            startLocalDiscovery(identity: identity, role: role)
          }
        #else
          startLocalDiscovery(identity: identity, role: role)
        #endif
      #endif

      // 3. Observe iCloud external changes
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

    /// Starts or stops local-network discovery for the holder's choice.
    ///
    /// iCloud sync and reconciliation run regardless; only the Bonjour
    /// advertisement and browse that summon the system prompt are gated.
    /// A stopped discovery cannot be restarted, so enabling builds a new one.
    public func setLocalDiscoveryEnabled(_ enabled: Bool) {
      #if canImport(Network)
        lock.lock()
        defer { lock.unlock() }
        if enabled {
          guard localDiscovery == nil else { return }
          guard
            let identity = coordinator?.localIdentity ?? (try? RappDeviceIdentity())
          else { return }
          startLocalDiscovery(identity: identity, role: discoveryRole())
        } else {
          let discovery = localDiscovery
          localDiscovery = nil
          discovery?.cancel()
        }
      #endif
    }

    /// Triggers an immediate reconciliation of the cloud directory against the local device vault.
    public func reconcile() {
      guard let coordinator else { return }
      let vault = RappDeviceVault()
      Task {
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
        await MainActor.run {
          NotificationCenter.default.post(
            name: Self.pairingsDidChangeNotification,
            object: nil
          )
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

    #if canImport(Network)
      /// Builds and starts one local discovery for the given identity.
      private func startLocalDiscovery(
        identity: RappDeviceIdentity,
        role: RappDeviceRole
      ) {
        let discovery = RappLocalDiscovery(
          localIdentity: identity,
          localRole: role,
          onLiveDevicesChanged: { [weak self] ids, names in
            self?.updateOnlineDevices(ids: ids, names: names)
          }
        )
        discovery.start()
        self.localDiscovery = discovery
      }
    #endif

    /// The role discovery announces, from the coordinator when it exists.
    private func discoveryRole() -> RappDeviceRole {
      if let role = coordinator?.localRole {
        return role
      }
      #if os(iOS)
        guard SupportedCardTransports.offersNearField else {
          return .requester
        }
        return .holder
      #else
        return .requester
      #endif
    }

    deinit {
      #if canImport(Network)
        localDiscovery?.cancel()
      #endif
      if let observer = externalChangeObserver {
        NotificationCenter.default.removeObserver(observer)
      }
    }
  }
#endif
