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
      /// off, everything remote stops at once.
      internal func remoteUseChanged() {
        guard Self.dialsPhones else { return }
        if Self.remoteUseOn {
          start()
        } else {
          stopFollowing()
        }
      }

      /// Stops following the phone as remote use turns off (CC-94).
      ///
      /// The session closes and the browse stops at once, the phone's
      /// identity leaves at once rather than after its grace, and what
      /// discovery learned is forgotten. The pairings stay, so turning
      /// remote use on again resumes without a new code.
      private func stopFollowing() {
        #if REFINEID_STREAM_TRANSPORT
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
    #endif
  }
#endif
