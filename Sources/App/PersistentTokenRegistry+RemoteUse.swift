// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)
  import CardCore
  import Foundation
  import os
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
      #if REFINEID_STREAM_TRANSPORT
        sessionSlot.isEstablished
      #else
        false
      #endif
    }

    #if os(macOS) && REFINEID_REMOTE_CARD
      #if REFINEID_STREAM_TRANSPORT
        /// Waits for `closes`, at most `limit`, answering whether the close
        /// left in time.
        nonisolated private static func settled(
          _ closes: Task<Bool, Never>, atMost limit: Duration
        ) async -> Bool {
          let pending = OSAllocatedUnfairLock<CheckedContinuation<Bool, Never>?>(initialState: nil)
          return await withCheckedContinuation { continuation in
            pending.withLock { $0 = continuation }
            let finish: @Sendable (Bool) -> Void = { left in
              let waiting = pending.withLock { waiting in
                defer { waiting = nil }
                return waiting
              }
              waiting?.resume(returning: left)
            }
            Task.detached { finish(await closes.value) }
            Task.detached {
              try? await Task.sleep(for: limit)
              finish(false)
            }
          }
        }
      #endif

    #endif

    #if os(macOS) && REFINEID_REMOTE_CARD
      /// Follows the switch: on, the paired phone is followed as at launch,
      /// or the code entry is offered; the holder's click off forgets every
      /// pairing; a stop withdraws and keeps the pairings.
      internal func remoteUseChanged(_ move: RemoteUseSwitch.Move) {
        guard Self.dialsPhones else { return }
        switch move {
        case .forgetting:
          forgetEveryPairing(
            in: RappDeviceVault(), store: .standard, directory: RappAutoPairingService.shared)

        case .stopped:
          withdraw()

        case .turnedOn:
          turnedOn(
            in: RappDeviceVault(), store: .standard, directory: RappAutoPairingService.shared)
        }
      }

      /// Follows the holder's click turning remote use on.
      ///
      /// A click off still forgetting follows once its pairings are gone.
      /// One left unfinished is tried again first, and while it cannot
      /// finish remote use stays off: a pairing the holder forgot is never
      /// followed, and its phone's same-account record never pairs again
      /// (CC-100).
      internal func turnedOn(
        in vault: RappDeviceVault,
        store: RemoteUseForgetting.Store,
        directory: any SameAccountDirectory
      ) {
        guard forgetting == nil else { return }
        guard RemoteUseForgetting.pending(in: store) == nil else {
          finishForgetting(after: nil, in: vault, store: store, directory: directory)
          return
        }
        start()
        RappAutoPairingService.shared.reconcile()
      }

      /// Forgets every pairing as the holder turns remote use off (RAPP
      /// v26.10.22 §4.6 item 6, CC-100).
      ///
      /// The click is stored in `store` first, with the pairings `vault`
      /// holds (``RemoteUseForgetting``). The phone's identity leaves at
      /// once and everything remote stops. An open session closes with
      /// `pairing_revoked`; once its close left, or after
      /// ``QuitWithdrawal/bound``, those pairings are destroyed with their
      /// keys and their phones leave the account's `directory`, off the
      /// main thread so a quit can wait on it. A phone with no session open
      /// is told nothing. A click off while an earlier one is still
      /// forgetting follows it.
      internal func forgetEveryPairing(
        in vault: RappDeviceVault,
        store: RemoteUseForgetting.Store,
        directory: any SameAccountDirectory
      ) {
        RemoteUseForgetting.request(
          at: RappPlatformClock().wallMilliseconds(), listing: vault, in: store)
        phoneThatForgot = nil
        #if REFINEID_STREAM_TRANSPORT
          let closes = revokeHolderSession()
        #else
          let closes: Task<Bool, Never>? = nil
        #endif
        withdraw()
        finishForgetting(after: closes, in: vault, store: store, directory: directory)
      }

      /// Finishes the stored click once `closes` left or its bound passed,
      /// off the main thread, and answers once the app followed.
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
        in vault: RappDeviceVault,
        store: RemoteUseForgetting.Store,
        directory: any SameAccountDirectory
      ) -> Task<Void, Never> {
        let clock = RappPlatformClock()
        let earlier = pairingDestruction
        forgettingGeneration += 1
        let generation = forgettingGeneration
        let destruction = Task.detached {
          if let earlier {
            _ = await earlier.value
          }
          #if REFINEID_STREAM_TRANSPORT
            if let closes {
              _ = await Self.settled(closes, atMost: QuitWithdrawal.bound)
            }
          #endif
          return await RemoteUseForgetting.finish(
            in: vault, store: store, clock: clock, directory: directory)
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
            RappAutoPairingService.shared.reconcile()
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
        NotificationCenter.default.post(
          name: RappPairingModel.pairingsDidChangeNotification, object: nil)
      }

      /// Turns `remoteUse` off once the last pairing in `vault` has ended
      /// other than by the holder's click: the phone revoked it, or it
      /// expired (CC-101).
      internal func remoteUseFollowsThePairings(
        _ remoteUse: RemoteUseSwitch, in vault: RappDeviceVault
      ) {
        guard remoteUse.isOn, !RappPairIdleExpiry.holdsActivePairing(vault) else { return }
        remoteUse.stop()
      }
    #endif

    /// This computer's withdrawal, as a card in its reader suspends remote
    /// use, as it quits, or as remote use stops (RAPP v26.10.22 §4.5 item
    /// 8, CC-98, CC-102).
    ///
    /// An open session closes with `service_withdrawn` and a dial under way
    /// ends without a notice. The browse stops at once, the phone's identity
    /// leaves at once rather than after its grace, and what discovery
    /// learned is forgotten. The pairings stay.
    internal func withdraw() {
      #if REFINEID_STREAM_TRANSPORT
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
      #endif
      localNetworkDenied = false
      Self.withdrawPublishedIdentity()
    }

    #if REFINEID_STREAM_TRANSPORT
      /// Ends the session as this computer withdraws (RAPP v26.10.22 §4.5
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
      /// v26.10.22 §4.6 item 6), answering whether its close left; nil
      /// when no session is open or being dialled.
      ///
      /// An open session closes with `pairing_revoked`; a dial under way
      /// ends without a notice.
      internal func revokeHolderSession() -> Task<Bool, Never>? {
        endHolderSession { session in await session.closePairingRevoked() }
      }

      /// Ends the open session with `pairing_revoked` when it runs over
      /// `pairID`, as the pairing is forgotten (RAPP v26.10.22 §4.6 item 1);
      /// false when no session over `pairID` is open or the close did not
      /// leave, so the pairing is kept forgotten for its next session.
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
    #endif
  }
#endif
