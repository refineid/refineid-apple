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
      /// Removes the same-account records of the phones `pairIDs` pair this
      /// computer with, so the account's directory does not pair them again.
      private static func removeSameAccountRecords(of pairIDs: [Data]) {
        let service = RappAutoPairingService.shared
        let localKey = service.localIdentity?.publicKeyData
        let names = Set(pairIDs.compactMap { RappPairNames.name(forPairID: $0)?.lowercased() })
        for device in service.remoteDevices where device.role == .holder {
          let derived = localKey.map { key in
            RappSameAccountPairBuilder.derivePairIdentifier(
              publicKeyA: key, publicKeyB: device.staticPublicKey)
          }
          let paired = derived.map(pairIDs.contains) ?? false
          if paired || names.contains(device.deviceName.lowercased()) {
            service.removeRemoteDevice(deviceID: device.deviceID)
          }
        }
      }

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
          forgetEveryPairing(in: RappDeviceVault())

        case .stopped:
          withdraw()

        case .turnedOn:
          start()
          RappAutoPairingService.shared.reconcile()
        }
      }

      /// Forgets every pairing as the holder turns remote use off (RAPP
      /// v26.10.22 §4.6 item 6, CC-100).
      ///
      /// The phone's identity leaves at once and everything remote stops.
      /// An open session closes with `pairing_revoked`; once its close left,
      /// or after ``QuitWithdrawal/bound``, every pairing this computer held
      /// is destroyed with its key. A phone with no session open is told
      /// nothing. A same-account record that would pair the phone again
      /// goes too. `vault` holds the pairings.
      internal func forgetEveryPairing(in vault: RappDeviceVault) {
        let pairIDs = (try? vault.activePairIDs()) ?? []
        phoneThatForgot = nil
        Self.removeSameAccountRecords(of: pairIDs)
        #if REFINEID_STREAM_TRANSPORT
          let closes = revokeHolderSession()
          withdraw()
          guard let closes else {
            destroy(pairIDs, in: vault)
            return
          }
          forgetting = Task { @MainActor [weak self] in
            _ = await Self.settled(closes, atMost: QuitWithdrawal.bound)
            guard let self else { return }
            forgetting = nil
            destroy(pairIDs, in: vault)
            if Self.followsPhone {
              start()
            }
          }
        #else
          withdraw()
          destroy(pairIDs, in: vault)
        #endif
      }

      /// Destroys every pairing `pairIDs` names, with its key and its name,
      /// and tells the rest of the app the pairings changed.
      private func destroy(_ pairIDs: [Data], in vault: RappDeviceVault) {
        let clock = RappPlatformClock()
        for pairID in pairIDs {
          do {
            try RappPairRevocation.revoke(pairID: pairID, in: vault, clock: clock)
          } catch {
            #if DEBUG
              DevErrorLog.report("pairing not destroyed: the vault refused", source: .app)
            #endif
          }
          RappPairNames.forget(pairID: pairID)
        }
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
