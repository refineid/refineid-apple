// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if (os(macOS) || os(iOS)) && REFINEID_STREAM_TRANSPORT
  import CardCore
  import Foundation
  import RappEngine

  extension PersistentTokenRegistry {
    /// One active pairing the holder's rotating hints can name.
    private struct HolderPairing: Sendable {
      let key: String
      let pairID: Data
      let rendezvousToken: Data
    }

    /// Seconds a vanished advertisement may stay missing before the
    /// borrowed identity is withdrawn.
    ///
    /// Bonjour browse results drop a live name for a moment without
    /// the holder having left.
    private static let advertisementLossHoldSeconds = 30

    private static var advertisementLossHold: Duration {
      Duration.seconds(advertisementLossHoldSeconds)
    }

    /// Every active pairing in the vault.
    private static func activeHolderPairings() -> [HolderPairing] {
      let vault = RappDeviceVault()
      let pairIDs = (try? vault.activePairIDs()) ?? []
      return pairIDs.compactMap { pairID in
        guard let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault) else {
          return nil
        }
        return HolderPairing(
          key: pairID.map { String(format: "%02x", $0) }.joined(),
          pairID: pairID,
          rendezvousToken: pair.metadata().rendezvousToken)
      }
    }

    /// The pairing a published session record belongs to.
    ///
    /// A record with hints names one of `pairings` through a hint; a
    /// minimal record names the only pairing, or an unknown one (the
    /// empty key) when there are several. Anything else is not a holder.
    nonisolated private static func holderKey(
      for record: [String: String], among pairings: [HolderPairing]
    ) -> String? {
      guard StreamRendezvousName.isSessionRecord(record) else { return nil }
      guard record[StreamRendezvousName.hintsKey] != nil else {
        return pairings.count == 1 ? pairings[0].key : ""
      }
      let now = Date()
      return pairings.first { pairing in
        StreamRendezvousName.sessionRecord(record, mayHold: pairing.rendezvousToken, at: now)
      }?.key
    }

    /// The classifier the browser calls on its own queue.
    ///
    /// Built outside the main actor so the closure carries no main-actor
    /// isolation; the browser queue would otherwise trap the runtime
    /// isolation check.
    nonisolated private static func recordClassifier(
      among pairings: [HolderPairing]
    ) -> @Sendable ([String: String]) -> String? {
      { record in holderKey(for: record, among: pairings) }
    }

    /// The change handler the browser calls on its own queue; it hops to
    /// the main actor for everything it touches.
    nonisolated private static func presenceHandler(
      pairIDs: [String: Data]
    ) -> @Sendable (Bool, String?) -> Void {
      { present, matchedName in
        Task { @MainActor in
          if present, let matchedName, let pairID = pairIDs[matchedName] {
            let vault = RappDeviceVault()
            if (try? vault.selectedPairID()) != pairID {
              try? vault.selectPair(pairID: pairID)
            }
          }
          Self.shared.holderPresenceChanged(present)
        }
      }
    }

    /// Browses for a holder in session mode whose hints name a pairing.
    ///
    /// The holder publishes only while it can serve a card. Losing that
    /// service means the reader card is gone: the borrowed identity is
    /// withdrawn. The pairing stays so the next card can use it. An NFC
    /// prime keeps the holder advertising.
    internal func startWatchingPresence() {
      guard Self.isRemoteCardEnabled else { return }
      guard !CardPresence.shared.isReaderCardPresent else {
        Self.withdrawPublishedIdentity()
        return
      }
      let pairings = Self.activeHolderPairings()
      guard !pairings.isEmpty else {
        stopWatchingPresence()
        Self.withdrawPublishedIdentity()
        return
      }
      let keys = Set(pairings.map(\.key))
      if let existing = presence, existing.matchingNames == keys {
        return
      }
      presence?.cancel()
      let pairIDs = Dictionary(uniqueKeysWithValues: pairings.map { ($0.key, $0.pairID) })
      let watcher = StreamRelayPresence(
        following: keys,
        classifyingRecord: Self.recordClassifier(among: pairings),
        onChange: Self.presenceHandler(pairIDs: pairIDs))
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
      guard Self.isRemoteCardEnabled else { return }
      guard !CardPresence.shared.isReaderCardPresent else {
        stopWatchingPresence()
        Self.withdrawPublishedIdentity()
        return
      }
      let pairings = Self.activeHolderPairings()
      guard !pairings.isEmpty else {
        stopWatchingPresence()
        Self.withdrawPublishedIdentity()
        return
      }
      let keys = Set(pairings.map(\.key))
      if let current = presence, current.matchingNames == keys {
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
      guard !Self.activeHolderPairings().isEmpty else {
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
      guard Self.isRemoteCardEnabled else { return }
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
