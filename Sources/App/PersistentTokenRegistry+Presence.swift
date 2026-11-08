// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)
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

    /// Seconds a vanished advertisement may stay missing before the holder
    /// counts as gone from the network and is no longer dialed.
    ///
    /// Bonjour browse results drop a live name for a moment without the
    /// holder having left. An open session and the offered identity do not
    /// follow the advertisement (RAPP v26.11.8 §4.5 item 6, §8.4 item 3).
    private static let advertisementLossHoldSeconds = 30

    private static var advertisementLossHold: Duration {
      Duration.seconds(advertisementLossHoldSeconds)
    }

    /// The stored pairings that serve: a forgotten one is the revocation
    /// backlog's alone, which delivers its close on a session of its own
    /// (RAPP v26.11.8 §4.6 item 6), so this watcher neither follows nor
    /// dials it.
    private static func activeHolderPairings() -> [HolderPairing] {
      let vault = RappDeviceVault()
      let pairIDs = (try? vault.activePairIDs()) ?? []
      return pairIDs.compactMap { pairID -> HolderPairing? in
        guard let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault),
          pair.metadata().forgottenAtMs == nil
        else { return nil }
        return HolderPairing(key: pairingKey(pairID), pairID: pairID, record: pair)
      }
    }

    /// The name a watcher follows a pairing by.
    internal static func pairingKey(_ pairID: Data) -> String {
      pairID.map { String(format: "%02x", $0) }.joined()
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
          let inSight = present ? matchedName.flatMap { pairIDs[$0] } : nil
          Self.shared.pairInSight = inSight
          if let pairID = inSight {
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
    /// The holder's record says it is on the network and worth dialing;
    /// whether a card can answer is what its session says (RAPP v26.11.8
    /// §8.4). Losing the record stops the dialing; the identity follows the
    /// session's word and its grace. The pairing stays so the next card can
    /// use it. Nothing browses while remote use is off.
    internal func startWatchingPresence() {
      guard Self.followsPhone else { return }
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
      dialAfterSettling()
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

    /// Restarts browsing for the currently selected holder, while remote
    /// use is on.
    internal func restartWatchingPresence() {
      followRevocationBacklog()
      guard Self.followsPhone else { return }
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

    /// The holder closed a session with `pairing_revoked` (RAPP v26.11.8
    /// §4.6 item 4).
    ///
    /// This computer forgets the pairing too, the borrowed identity leaves
    /// at once, and the row names the phone that did it above the pairing
    /// prompt. Remote use stays on: only the holder turns it off.
    internal func holderRevoked(pairID: Data, in vault: RappDeviceVault) {
      connectedAfterPairing()
      let name = (try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault))?.metadata()
        .peerDisplayName
      if holderSession?.pairID == pairID {
        closeHolderSession()
      }
      try? RappPairRevocation.revoke(pairID: pairID, in: vault, clock: RappPlatformClock())
      if (try? vault.selectedPairID()) == pairID {
        try? vault.clearSelectedPair()
      }
      advertisementLossTask?.cancel()
      advertisementLossTask = nil
      holderIsAdvertising = false
      Self.withdrawPublishedIdentity()
      refreshPairing(in: vault)
      if let name {
        phoneThatForgot = name
      }
      restartWatchingPresence()
      NotificationCenter.default.post(
        name: RappPairingModel.pairingsDidChangeNotification, object: nil)
    }

    /// A one-shot requester session of this process heard `pairing_revoked`
    /// (RAPP v26.11.8 §4.6 item 4): the identity leaves at once, as on the
    /// held session, when it was published for a pairing the vault no longer
    /// holds.
    ///
    /// The notice names no pairing and says only where to look. The vault
    /// decides, so a notice that reaches here without a revocation behind it
    /// changes nothing, and a vault that does not answer changes nothing.
    internal func pairingEndNoticed(published pairID: Data?, in vault: RappDeviceVault) {
      guard let pairID, (try? vault.pairIsGone(pairID: pairID)) == true else { return }
      holderRevoked(pairID: pairID, in: vault)
    }

    /// The phone echoed this computer's close for a pairing it forgot (RAPP
    /// v26.11.8 §4.6 items 3 and 6): the record and its key go now.
    internal func revocationNoticeDelivered(pairID: Data) {
      revocationNoticeDelivered(pairID: pairID, in: RappDeviceVault())
    }

    /// As ``revocationNoticeDelivered(pairID:)``, for a pairing in `vault`.
    internal func revocationNoticeDelivered(pairID: Data, in vault: RappDeviceVault) {
      try? RappPairRevocation.revoke(pairID: pairID, in: vault, clock: RappPlatformClock())
      refreshPairing(in: vault)
      followRevocationBacklog(in: vault)
      restartWatchingPresence()
      NotificationCenter.default.post(
        name: RappPairingModel.pairingsDidChangeNotification, object: nil)
    }

    /// The holder announced that it stopped serving, in a withdrawn record
    /// or in its session's `service_withdrawn` close (RAPP v26.11.8 §4.5
    /// item 6): the borrowed identity leaves at once, without the hold an
    /// unannounced loss gets, and no stream dial goes out until the
    /// holder's session record is seen again.
    internal func holderWithdrew() {
      connectedAfterPairing()
      advertisementLossTask?.cancel()
      advertisementLossTask = nil
      holderIsAdvertising = false
      closeHolderSession()
      Self.withdrawPublishedIdentity()
      // Bluetooth carries no withdrawal record: its next dial waits for
      // the phone's advertisement (§4.5 items 5 and 6).
      if transportPolicy.nextDial == .bluetooth {
        scheduleRedial()
      }
    }

    internal func holderPresenceChanged(_ present: Bool) {
      // A report the browser sent before remote use was turned off
      // changes nothing.
      guard Self.followsPhone else { return }
      holderRecordListed = present
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
          streamFailedInSight = false
          bluetoothUsable = Self.dialsOverBluetooth
          sessionSlot.startOver()
          // The announcement is dialled at once: a Bluetooth dial still
          // scanning for the phone gives way to the stream.
          if sessionSlot.state == .dialing(.bluetooth) {
            holderSession?.close()
            forgetHeldSession()
          }
        }
        advertisementLossTask?.cancel()
        advertisementLossTask = nil
        holderIsAdvertising = true
        openHolderSession()
        return
      }
      guard holderIsAdvertising else { return }
      armAdvertisementLossHold()
      // With the record gone, a phone that is still near is reached over
      // Bluetooth; an open session stays whatever its transport.
      openHolderSession()
    }

    /// Marks the holder gone from the network unless the browser reports it
    /// within ``advertisementLossHold``; an open session stays, and the
    /// offered identity follows its grace (§4.5 item 6, §8.4 item 3).
    internal func armAdvertisementLossHold() {
      guard advertisementLossTask == nil else { return }
      advertisementLossTask = Task { @MainActor in
        try? await Task.sleep(for: Self.advertisementLossHold)
        guard !Task.isCancelled else { return }
        advertisementLossTask = nil
        holderIsAdvertising = false
        bluetoothUsable = Self.dialsOverBluetooth
        #if DEBUG
          print("[persistent-token] holder left the network")
          fflush(stdout)
        #endif
        // Off the network, the phone may still be in Bluetooth range.
        openHolderSession()
      }
    }

    internal func installPairingObservers() {
      guard Self.dialsPhones else { return }
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
