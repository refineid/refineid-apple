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
      let record: RappPairRecord
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

    /// Every stored pairing in the vault, a forgotten one too: its hint
    /// brings the session that delivers its close (RAPP v26.10.21 §4.6 item
    /// 2).
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
          record: pair)
      }
    }

    /// What a published record says about one of `pairings`.
    ///
    /// A session record carrying a pairing's discovery hint names the
    /// pairing as served; a withdrawn record names the pairing whose
    /// withdrawal hint it carries for `instance`. Anything else is not a
    /// holder.
    nonisolated private static func classification(
      of record: [String: String], instance: String, among pairings: [HolderPairing]
    ) -> StreamRelayPresence.Classification? {
      let now = Date()
      if let holder = pairings.first(where: { pairing in
        StreamRendezvousName.sessionRecord(record, holds: pairing.record, at: now)
      }) {
        return .holder(holder.key)
      }
      if let withdrawn = pairings.first(where: { pairing in
        StreamRendezvousName.withdrawnRecord(
          record, instance: instance, withdraws: pairing.record, at: now)
      }) {
        return .withdrawn(withdrawn.key)
      }
      return nil
    }

    /// The classifier the browser calls on its own queue.
    ///
    /// Built outside the main actor so the closure carries no main-actor
    /// isolation; the browser queue would otherwise trap the runtime
    /// isolation check.
    nonisolated private static func recordClassifier(
      among pairings: [HolderPairing]
    ) -> @Sendable ([String: String], String) -> StreamRelayPresence.Classification? {
      { record, instance in classification(of: record, instance: instance, among: pairings) }
    }

    /// The withdrawal handler the browser calls on its own queue.
    nonisolated private static func withdrawalHandler() -> @Sendable (String) -> Void {
      { _ in
        Task { @MainActor in
          Self.shared.holderWithdrew()
        }
      }
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
            let forgotten =
              (try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault))?.metadata()
              .forgottenAtMs != nil
            if !forgotten, (try? vault.selectedPairID()) != pairID {
              try? vault.selectPair(pairID: pairID)
            }
          }
          Self.shared.holderPresenceChanged(present)
        }
      }
    }

    /// Browses for a holder in session mode whose hints name a pairing.
    ///
    /// The holder's record says it is on the network; whether a card can
    /// answer is what its session says (RAPP v26.10.21 §8.4). Losing the
    /// record ends the session and withdraws the borrowed identity. The
    /// pairing stays so the next card can use it.
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
        onChange: Self.presenceHandler(pairIDs: pairIDs),
        onWithdrawn: Self.withdrawalHandler())
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
        holderIsAdvertising = false
        closeHolderSession()
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
        openHolderSession()
        return
      }
      stopWatchingPresence(clearHold: !holderIsAdvertising)
      startWatchingPresence()
    }

    /// The holder closed a session with `pairing_revoked` (RAPP v26.10.21
    /// §4.6 item 4): this computer forgets the pairing too, the borrowed
    /// identity leaves at once, and the row names the phone that did it.
    internal func holderRevoked(pairID: Data) {
      let vault = RappDeviceVault()
      let name = RappPairNames.name(forPairID: pairID)
      if holderSession?.pairID == pairID {
        closeHolderSession()
      }
      try? RappPairRevocation.revoke(pairID: pairID, in: vault, clock: RappPlatformClock())
      RappPairNames.forget(pairID: pairID)
      if (try? vault.selectedPairID()) == pairID {
        try? vault.clearSelectedPair()
      }
      advertisementLossTask?.cancel()
      advertisementLossTask = nil
      holderIsAdvertising = false
      Self.withdrawPublishedIdentity()
      refreshPairing()
      if let name {
        phoneThatForgot = name
      }
      restartWatchingPresence()
      NotificationCenter.default.post(
        name: RappPairingModel.pairingsDidChangeNotification, object: nil)
    }

    /// This computer's close for a pairing it forgot reached the phone
    /// (RAPP v26.10.21 §4.6 items 2 and 3): the record and its key go now.
    internal func revocationNoticeDelivered(pairID: Data) {
      try? RappPairRevocation.revoke(
        pairID: pairID, in: RappDeviceVault(), clock: RappPlatformClock())
      refreshPairing()
      restartWatchingPresence()
      NotificationCenter.default.post(
        name: RappPairingModel.pairingsDidChangeNotification, object: nil)
    }

    /// The holder announced that it stopped serving: the borrowed identity
    /// leaves at once, without the hold an unannounced loss gets, and no
    /// request goes out until the holder advertises a session again.
    internal func holderWithdrew() {
      advertisementLossTask?.cancel()
      advertisementLossTask = nil
      holderIsAdvertising = false
      closeHolderSession()
      Self.withdrawPublishedIdentity()
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
        holderIsAdvertising = false
        closeHolderSession()
        Self.withdrawPublishedIdentity()
        return
      }
      if present {
        // A newly seen advertisement is a fresh reason to dial: give the
        // redial loop a new deadline (R-58). Only on the transition, so a
        // phone that keeps advertising while the session cannot establish
        // does not reset the deadline forever.
        if !holderIsAdvertising {
          continuousFailureSince = nil
        }
        advertisementLossTask?.cancel()
        advertisementLossTask = nil
        holderIsAdvertising = true
        openHolderSession()
        return
      }
      guard holderIsAdvertising || certificateDER != nil else { return }
      armAdvertisementLossHold()
    }

    /// Ends the session and withdraws the borrowed identity unless the
    /// browser reports the holder within ``advertisementLossHold``.
    internal func armAdvertisementLossHold() {
      guard advertisementLossTask == nil else { return }
      advertisementLossTask = Task { @MainActor in
        try? await Task.sleep(for: Self.advertisementLossHold)
        guard !Task.isCancelled else { return }
        advertisementLossTask = nil
        holderIsAdvertising = false
        closeHolderSession()
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
          self?.refreshPairing()
          self?.restartWatchingPresence()
        }
      }
      pairingsObservers = [observer1]
    }
  }
#endif
