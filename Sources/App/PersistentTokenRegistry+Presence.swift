// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if (os(macOS) || os(iOS)) && REFINEID_STREAM_TRANSPORT
  import CardCore
  import Foundation
  import RappEngine

  extension PersistentTokenRegistry {
    /// Seconds a vanished advertisement may stay missing before the
    /// borrowed identity is withdrawn.
    ///
    /// Bonjour browse results drop a live name for a moment without
    /// the holder having left.
    private static let advertisementLossHoldSeconds = 30

    private static var advertisementLossHold: Duration {
      Duration.seconds(advertisementLossHoldSeconds)
    }

    /// All published names derived from all active pairings in the vault, mapped to pair IDs.
    private static func activeHolderServiceNames() -> [String: Data] {
      let vault = RappDeviceVault()
      let pairIDs = (try? vault.activePairIDs()) ?? []
      var mapping: [String: Data] = [:]
      for pairID in pairIDs {
        guard let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault) else {
          continue
        }
        let serviceName = StreamRendezvousName.name(sharing: pair.metadata().rendezvousToken)
        mapping[serviceName] = pairID
      }
      return mapping
    }

    /// Browses for the selected pair's holder advertisement.
    ///
    /// The holder publishes only while it can serve a card. Losing that
    /// service means the reader card is gone: the borrowed identity is
    /// withdrawn. The pairing stays so the next card can use it. An NFC
    /// prime keeps the holder advertising.
    internal func startWatchingPresence() {
      guard !CardPresence.shared.isReaderCardPresent else {
        Self.withdrawPublishedIdentity()
        return
      }
      let services = Self.activeHolderServiceNames()
      guard !services.isEmpty else {
        stopWatchingPresence()
        Self.withdrawPublishedIdentity()
        return
      }
      let names = Set(services.keys)
      if let existing = presence, existing.matchingNames == names {
        return
      }
      presence?.cancel()
      let watcher = StreamRelayPresence(matching: names) { present, matchedName in
        Task { @MainActor in
          if present, let matchedName, let pairID = services[matchedName] {
            let vault = RappDeviceVault()
            if (try? vault.selectedPairID()) != pairID {
              try? vault.selectPair(pairID: pairID)
            }
          }
          Self.shared.holderPresenceChanged(present)
        }
      }
      presence = watcher
      watcher.start()
    }

    /// Puts wireless presence watching into passive state by cancelling
    /// the active Bonjour browse and pending loss tasks.
    internal func stopWatchingPresence() {
      stopWatchingPresence(clearHold: true)
    }

    /// Puts wireless presence watching into passive state by cancelling
    /// the active Bonjour browse, optionally preserving pending loss tasks.
    internal func stopWatchingPresence(clearHold: Bool) {
      presence?.cancel()
      presence = nil
      if clearHold {
        advertisementLossTask?.cancel()
        advertisementLossTask = nil
        hasSeenHolderAdvertisement = false
        holderIsAdvertising = false
      }
    }

    /// Restarts browsing for the currently selected holder.
    internal func restartWatchingPresence() {
      guard !CardPresence.shared.isReaderCardPresent else {
        stopWatchingPresence()
        Self.withdrawPublishedIdentity()
        return
      }
      let services = Self.activeHolderServiceNames()
      guard !services.isEmpty else {
        stopWatchingPresence()
        Self.withdrawPublishedIdentity()
        return
      }
      let names = Set(services.keys)
      if let current = presence, current.matchingNames == names {
        if certificateDER == nil,
          holderIsAdvertising || RappAutoPairingService.shared.isAnyPairedPeerOnline
        {
          startFetch(replacing: false)
        }
        return
      }
      stopWatchingPresence(clearHold: !holderIsAdvertising)
      startWatchingPresence()
    }

    internal func holderPresenceChanged(_ present: Bool) {
      if CardPresence.shared.isReaderCardPresent {
        stopWatchingPresence()
        Self.withdrawPublishedIdentity()
        return
      }
      guard !Self.activeHolderServiceNames().isEmpty else {
        advertisementLossTask?.cancel()
        advertisementLossTask = nil
        hasSeenHolderAdvertisement = false
        holderIsAdvertising = false
        Self.withdrawPublishedIdentity()
        return
      }
      if present {
        advertisementLossTask?.cancel()
        advertisementLossTask = nil
        hasSeenHolderAdvertisement = true
        holderIsAdvertising = true
        resetFetchFailures()
        if certificateDER == nil {
          startFetch(replacing: false)
        } else {
          seedHolderLine()
        }
        return
      }
      guard hasSeenHolderAdvertisement, holderIsAdvertising else { return }
      advertisementLossTask?.cancel()
      advertisementLossTask = Task { @MainActor in
        try? await Task.sleep(for: Self.advertisementLossHold)
        guard !Task.isCancelled else { return }
        holderIsAdvertising = false
        Self.withdrawPublishedIdentity()
        #if DEBUG
          print("[persistent-token] holder left, withdrew identity")
          fflush(stdout)
        #endif
      }
    }

    internal func installPairingObservers() {
      guard pairingsObservers.isEmpty else { return }
      let notificationCenter = NotificationCenter.default
      let observer1 = notificationCenter.addObserver(
        forName: RappPairingModel.pairingsDidChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.restartWatchingPresence()
        }
      }
      let observer2 = notificationCenter.addObserver(
        forName: RappAutoPairingService.pairingsDidChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.restartWatchingPresence()
        }
      }
      pairingsObservers = [observer1, observer2]
    }
  }
#endif
