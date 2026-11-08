// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)
  import CardCore
  import Foundation
  import RappEngine

  /// The registry's gate on remote use, and on the Mac its answer to the
  /// remote-use switch, which is the pairing (hierarchy specification §5.2).
  extension PersistentTokenRegistry {
    /// Whether remote use is on, read at each decision.
    ///
    /// The Mac's switch; an iPad has no switch and follows its paired phone
    /// whenever it dials phones.
    internal static var remoteUseOn: Bool {
      #if os(macOS)
        RemoteAccessGate.isEnabled
      #else
        true
      #endif
    }

    /// Whether this device follows its paired phone now: it dials phones and
    /// remote use is on.
    ///
    /// While it does not, nothing browses, scans, dials or offers the
    /// phone's identity (CC-100).
    internal static var followsPhone: Bool {
      dialsPhones && remoteUseOn
    }

    /// Whether a session with the phone is up: dialled and established.
    internal var holderSessionOpen: Bool {
      sessionSlot.isEstablished
    }

    #if os(macOS) && REFINEID_REMOTE_CARD
      /// Follows the switch: on, the paired phone is followed as at launch,
      /// or the code entry is offered; the holder's click off forgets every
      /// pairing; a stop withdraws and keeps the pairings.
      internal func remoteUseChanged(_ move: RemoteUseSwitch.Move) {
        guard Self.dialsPhones else { return }
        switch move {
        case .forgetting:
          forgetEveryPairing(in: RappDeviceVault(), store: .standard)

        case .stopped:
          withdraw()

        case .turnedOn:
          turnedOn(in: RappDeviceVault(), store: .standard)
        }
      }

      /// Follows the holder's click turning remote use on.
      ///
      /// A click off still forgetting follows once its pairings are gone.
      /// One left unfinished is tried again first, and while it cannot
      /// finish remote use stays off: a pairing the holder forgot is never
      /// followed (CC-100).
      internal func turnedOn(in vault: RappDeviceVault, store: RemoteUseForgetting.Store) {
        guard forgetting == nil else { return }
        guard RemoteUseForgetting.pending(in: store) == nil else {
          finishForgetting(after: nil, closing: nil, in: vault, store: store)
          return
        }
        start()
      }

      /// Forgets the pairing as the holder turns remote use off (RAPP
      /// v26.11.2 §4.6 item 6, CC-100, CC-118).
      ///
      /// The click is stored in `store` first, with the pairings `vault`
      /// holds (``RemoteUseForgetting``). The phone's identity leaves at
      /// once and everything remote stops but the revocation backlog. An
      /// open session closes with `pairing_revoked` and waits for its echo;
      /// on the echo its pairing is destroyed. Every other pairing, and that
      /// one without the echo, is stored forgotten, off the main thread so
      /// a quit can wait on it, and waits in the backlog for its phone. A
      /// click off while an earlier one is still forgetting follows it.
      internal func forgetEveryPairing(
        in vault: RappDeviceVault, store: RemoteUseForgetting.Store
      ) {
        RemoteUseForgetting.request(
          at: RappPlatformClock().wallMilliseconds(), listing: vault, in: store)
        phoneThatForgot = nil
        let closing = holderSession?.pairID
        let closes = revokeHolderSession()
        withdraw()
        finishForgetting(after: closes, closing: closing, in: vault, store: store)
      }

      /// Finishes the stored click off the main thread, and answers once the
      /// app followed.
      ///
      /// It waits for `closes`, the `pairing_revoked` close of the session
      /// over `closing`; a close the phone echoed destroys `closing`, and
      /// the click then stores the rest forgotten.
      ///
      /// One destruction runs at a time: this one starts once any still
      /// running has ended, and a quit waiting on the latest waits on all.
      /// Only the latest one, on the main actor, lets go of the in-flight
      /// state and follows: with remote use on again, the paired phone is
      /// followed once nothing a click forgets is left, and remote use goes
      /// off while something is.
      @discardableResult
      internal func finishForgetting(
        after closes: Task<Bool, Never>?,
        closing: Data?,
        in vault: RappDeviceVault,
        store: RemoteUseForgetting.Store
      ) -> Task<Void, Never> {
        let clock = RappPlatformClock()
        let earlier = pairingDestruction
        forgettingGeneration += 1
        let generation = forgettingGeneration
        let destruction = Task.detached {
          if let earlier {
            _ = await earlier.value
          }
          if let closes, await closes.value, let closing {
            try? RappPairRevocation.revoke(pairID: closing, in: vault, clock: clock)
          }
          return RemoteUseForgetting.finish(in: vault, store: store, clock: clock)
        }
        pairingDestruction = destruction
        let following = Task { @MainActor [weak self] in
          let outcome = await destruction.value
          guard let self else { return }
          forgotten(outcome, in: vault)
          guard forgettingGeneration == generation else { return }
          pairingDestruction = nil
          forgetting = nil
          guard Self.followsPhone else { return }
          if RemoteUseForgetting.pending(in: store) == nil {
            start()
          } else {
            RemoteUseSwitch.shared.stop()
          }
        }
        forgetting = following
        return following
      }

      /// Follows what forgetting the pairings did: a failure is reported,
      /// the row follows what `vault` holds, and the rest of the app learns
      /// the pairings changed.
      private func forgotten(_ outcome: RemoteUseForgetting.Outcome, in vault: RappDeviceVault) {
        RemoteUseForgetting.report(outcome)
        refreshPairing(in: vault)
        followRevocationBacklog(in: vault)
        NotificationCenter.default.post(
          name: RappPairingModel.pairingsDidChangeNotification, object: nil)
      }
    #endif

    /// This computer's withdrawal, as a card in its reader suspends remote
    /// use, as it quits, or as remote use stops (RAPP v26.11.2 §4.5 item
    /// 8, CC-98, CC-102).
    ///
    /// An open session closes with `service_withdrawn` and a dial under way
    /// ends without a notice. The browse stops at once, the phone's identity
    /// leaves at once rather than after its grace, and what discovery
    /// learned is forgotten. The pairings stay.
    internal func withdraw() {
      withdrawHolderSession()
      stopWatchingPresence()
      offerLapseTask?.cancel()
      offerLapseTask = nil
      identityOffer = RemoteIdentityOffer(unconfirmedSince: .now)
      holderRecordListed = false
      pairInSight = nil
      streamFailedInSight = false
      sessionSlot = RequesterSessionSlot()
      bluetoothPeers = RequesterBluetoothPeers()
      bluetoothUsable = Self.dialsOverBluetooth
      continuousFailureSince = nil
      localNetworkDenied = false
      Self.withdrawPublishedIdentity()
    }

    /// Ends the session as this computer withdraws (RAPP v26.11.2 §4.5
    /// item 8), answering whether its close left; nil when no session
    /// is open or being dialled.
    ///
    /// An open session closes with `service_withdrawn`, a dial under
    /// way ends without a notice, and no dial is left waiting. The
    /// pairing stays.
    @discardableResult
    internal func withdrawHolderSession() -> Task<Bool, Never>? {
      endHolderSession { session in await session.closeServiceWithdrawn() }
    }

    /// Ends the session as the holder forgets every pairing (RAPP
    /// v26.11.2 §4.6 item 6), answering whether the phone echoed its
    /// close; nil when no session is open or being dialled.
    ///
    /// An open session closes with `pairing_revoked`; a dial under way
    /// ends without a notice.
    internal func revokeHolderSession() -> Task<Bool, Never>? {
      endHolderSession { session in await session.closePairingRevoked() }
    }

    /// Ends the open session with `pairing_revoked` when it runs over
    /// `pairID`, as the pairing is forgotten (RAPP v26.11.2 §4.6 items 1
    /// and 6), answering whether the phone echoed the close; false when no
    /// session over `pairID` is open or no echo came, so the pairing is kept
    /// forgotten in the revocation backlog for its next session.
    internal func closeSessionForRevocation(pairID: Data) async -> Bool {
      guard let session = holderSession, session.pairID == pairID else { return false }
      redialTask?.cancel()
      redialTask = nil
      holderCardStatus = nil
      forgetHeldSession()
      let told = await session.closePairingRevoked()
      Self.withdrawPublishedIdentity()
      return told
    }

    /// Forgets every pairing but `kept`, the one just made: a requester
    /// holds one active pairing, and pairing another phone forgets the one
    /// it replaces (RAPP v26.11.2 §4.6 item 6, CC-118).
    ///
    /// Each replaced pairing is stored forgotten at once, so it serves
    /// nothing more. An open session over one closes with `pairing_revoked`
    /// and waits for its echo, which destroys it; every other one waits in
    /// the revocation backlog until its phone next appears and echoes the
    /// close, or its idle expiry passes.
    internal func forgetReplacedPairings(keeping kept: Data, in vault: RappDeviceVault) {
      let replaced = ((try? vault.activePairIDs()) ?? []).filter { $0 != kept }
      guard !replaced.isEmpty else { return }
      let clock = RappPlatformClock()
      let forgottenAt = clock.wallMilliseconds()
      for pairID in replaced {
        guard let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault),
          pair.metadata().forgottenAtMs == nil
        else { continue }
        do {
          try RappPairRevocation.forget(pair, in: vault, at: forgottenAt)
        } catch {
          #if DEBUG
            DevErrorLog.report("replaced pairing not forgotten: the vault refused", source: .app)
          #endif
        }
      }
      Task { @MainActor [weak self] in
        for pairID in replaced {
          let echoed = await self?.closeSessionForRevocation(pairID: pairID) == true
          guard echoed else { continue }
          try? RappPairRevocation.revoke(pairID: pairID, in: vault, clock: clock)
        }
        self?.refreshPairing(in: vault)
        self?.followRevocationBacklog(in: vault)
        NotificationCenter.default.post(
          name: RappPairingModel.pairingsDidChangeNotification, object: nil)
      }
    }

    /// The app is active again, perhaps back from the settings where the
    /// holder allowed the local network: a denial seen earlier is
    /// forgotten and the paired phone dialled afresh at once, so a denial
    /// that stands is seen again on that dial.
    internal func retryAfterLocalNetworkDenial() {
      guard localNetworkDenied else { return }
      localNetworkDenied = false
      guard Self.followsPhone, pairedPhoneID != nil else { return }
      continuousFailureSince = nil
      openHolderSession()
    }

    /// Lets go of the session and closes it with `close`, answering
    /// whether its close left.
    private func endHolderSession(
      _ close: @escaping @Sendable (RappHeldRequesterSession) async -> Bool
    ) -> Task<Bool, Never>? {
      redialTask?.cancel()
      redialTask = nil
      settleDialTask?.cancel()
      settleDialTask = nil
      holderCardStatus = nil
      guard let session = holderSession else { return nil }
      let established = sessionSlot.isEstablished
      forgetHeldSession()
      return Task.detached {
        let told = await close(session)
        #if DEBUG
          if established, !told {
            DevErrorLog.report("phone session: closing notice did not leave", source: .app)
          }
        #endif
        return told
      }
    }
  }
#endif
