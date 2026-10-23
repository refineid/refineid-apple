// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)
  import CardCore
  import Foundation

  /// The registry's gate on remote use, and on the Mac its answer to the
  /// remote-use switch (hierarchy specification §5.2).
  extension PersistentTokenRegistry {
    /// Whether the holder has remote use on, read at each decision.
    ///
    /// The Mac's switch, off by default; an iPad has no switch and follows
    /// its paired phone whenever it dials phones.
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
    /// phone's identity (CC-94).
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

    #if os(macOS)
      /// Follows the switch: on, the paired phone is followed as at launch;
      /// off, this computer withdraws and everything remote stops at once.
      internal func remoteUseChanged() {
        guard Self.dialsPhones else { return }
        if Self.remoteUseOn {
          start()
        } else {
          stopFollowing()
        }
      }

      /// Stops following the phone as remote use turns off: this
      /// computer's withdrawal (RAPP v26.10.22 §4.5 item 8, CC-94, CC-98).
      ///
      /// An open session closes with `service_withdrawn` and a dial under
      /// way ends without a notice. The browse stops at once, the phone's
      /// identity leaves at once rather than after its grace, and what
      /// discovery learned is forgotten. The pairings stay, so turning
      /// remote use on again resumes without a new code.
      private func stopFollowing() {
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
          redialTask?.cancel()
          redialTask = nil
          settleDialTask?.cancel()
          settleDialTask = nil
          holderCardStatus = nil
          guard let session = holderSession else { return nil }
          let established = sessionSlot.isEstablished
          forgetHeldSession()
          return Task.detached {
            let told = await session.closeServiceWithdrawn()
            #if DEBUG
              if established, !told {
                DevErrorLog.report("phone session: withdrawal close did not leave", source: .app)
              }
            #endif
            return told
          }
        }
      #endif
    #endif
  }
#endif
