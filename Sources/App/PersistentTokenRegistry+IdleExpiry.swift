// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)
  import CardCore
  import Foundation
  import RappEngine

  /// Idle expiry of the requester's pairings (RAPP v26.10.29 §4.6 item 5):
  /// a pairing with no established session for 30 days expires silently.
  extension PersistentTokenRegistry {
    /// The pairings a session is established to now.
    private var establishedPairings: Set<Data> {
      guard sessionSlot.isEstablished, let pairID = holderSession?.pairID else { return [] }
      return [pairID]
    }

    /// Sweeps every pairing for idle expiry at launch (RAPP v26.10.29 §4.6
    /// item 5), before anything remote starts, answering whether an active
    /// pairing remains.
    ///
    /// No session is established yet, and nothing else follows: the launch
    /// starts from what the vault then holds.
    @discardableResult
    internal static func sweepIdlePairingsAtLaunch() -> Bool {
      let vault = RappDeviceVault()
      reportSweep(
        RappPairIdleExpiry.sweep(
          in: vault, nowMilliseconds: RappPlatformClock().wallMilliseconds(), established: []))
      return RappPairIdleExpiry.holdsActivePairing(vault)
    }

    /// Records the session to `pairID` in its pairing's stored record, as
    /// it is established and as it ends (RAPP v26.10.29 §4.6 item 5).
    internal static func recordSession(pairID: Data) {
      let recorded = RappPairIdleExpiry.recordSession(
        pairID: pairID, in: RappDeviceVault(),
        nowMilliseconds: RappPlatformClock().wallMilliseconds())
      #if DEBUG
        if !recorded {
          DevErrorLog.report("pairing: session time not stored", source: .app)
        }
      #endif
    }

    /// Names a sweep's failures among the development errors.
    private static func reportSweep(_ sweep: RappPairIdleExpiry.Sweep) {
      #if DEBUG
        if sweep.failures > 0 {
          DevErrorLog.report(
            "pairing idle expiry: \(sweep.failures) pairing(s) not swept", source: .app)
        }
      #endif
    }

    /// Sweeps every pairing for idle expiry while the app runs (RAPP
    /// v26.10.29 §4.6 item 5).
    ///
    /// A pairing the open session runs over is recorded instead. One that
    /// expired leaves silently: its identity is withdrawn, the row follows
    /// the vault, and on the Mac remote use turns off when it was the last.
    internal func sweepIdlePairings() {
      let sweep = RappPairIdleExpiry.sweep(
        in: RappDeviceVault(), nowMilliseconds: RappPlatformClock().wallMilliseconds(),
        established: establishedPairings)
      Self.reportSweep(sweep)
      if !sweep.expired.isEmpty {
        pairingsExpired(sweep.expired)
      }
    }

    /// Withdraws what the expired pairings offered, and follows what the
    /// vault holds now; nothing is sent or shown.
    private func pairingsExpired(_ pairIDs: [Data]) {
      if let published = Self.publishedPairID(), pairIDs.contains(published) {
        Self.withdrawPublishedIdentity()
      }
      // A dial still under way over an expired pairing ends; one
      // established would have kept it.
      if let dialing = holderSession?.pairID, pairIDs.contains(dialing) {
        closeHolderSession()
      }
      refreshPairing()
      restartWatchingPresence()
      #if os(macOS) && REFINEID_REMOTE_CARD
        remoteUseFollowsThePairings(.shared, in: RappDeviceVault())
      #endif
      NotificationCenter.default.post(
        name: RappPairingModel.pairingsDidChangeNotification, object: nil)
    }
  }
#endif
