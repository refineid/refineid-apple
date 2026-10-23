// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import Foundation
  import RappEngine

  /// The holder's click turning remote use off, kept until every pairing it
  /// forgets is destroyed (RAPP v26.10.22 §4.6 item 6, STPA CC-100).
  ///
  /// The click is stored with its wall-clock time before anything else
  /// happens. Every pairing created up to that time is then destroyed with
  /// its key, and its name goes once its key is gone; a pairing made after
  /// the click stays. A pairing the vault does not let go stays under the
  /// stored click, which the next launch finishes before it decides whether
  /// to restore remote use, so no launch restores remote use on after the
  /// holder turned it off.
  internal enum RemoteUseForgetting {
    /// What one attempt to finish the forgetting did.
    internal struct Outcome: Equatable, Sendable {
      /// The pairings destroyed.
      internal var destroyed: [Data] = []

      /// How many pairings, or listings of them, the vault refused; each
      /// is tried again by the next attempt.
      internal var failures = 0
    }

    /// Where the click is kept: the app's defaults, or a suite of their
    /// own.
    internal struct Store: Sendable {
      /// The app's defaults.
      internal static let standard = Self(suiteName: nil)

      /// The defaults suite, or nil for the app's own.
      internal let suiteName: String?

      fileprivate var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
      }
    }

    /// The defaults key the click's time is stored under.
    internal static let requestedAtKey = "fi.refineid.rapp.forget-pairings-created-by-ms"

    /// The time of the holder's click whose forgetting is not finished, in
    /// milliseconds since the Unix epoch; nil when none is pending.
    internal static func requestedAt(in store: Store) -> UInt64? {
      store.defaults.object(forKey: requestedAtKey) as? UInt64
    }

    /// Stores the holder's click at `atMilliseconds` before the forgetting
    /// starts; a later click covers an earlier one still pending.
    internal static func request(at atMilliseconds: UInt64, in store: Store) {
      let covering = max(requestedAt(in: store) ?? atMilliseconds, atMilliseconds)
      store.defaults.set(covering, forKey: requestedAtKey)
    }

    /// Destroys every pairing in `vault` created up to the pending click,
    /// and clears the click once none is left; nothing without a click.
    ///
    /// Runs on any thread: quitting waits on it while the main thread
    /// answers the quit.
    internal static func finish(
      in vault: RappDeviceVault, store: Store, clock: RappPlatformClock
    ) -> Outcome {
      var outcome = Outcome()
      guard let requestedAt = requestedAt(in: store) else { return outcome }
      let pairIDs: [Data]
      do {
        pairIDs = try vault.activePairIDs()
      } catch {
        outcome.failures += 1
        return outcome
      }
      for pairID in pairIDs {
        let created = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault)
          .metadata().createdAtMs
        if let created, created > requestedAt { continue }
        do {
          try RappPairRevocation.revoke(pairID: pairID, in: vault, clock: clock)
        } catch {
          outcome.failures += 1
          continue
        }
        RappPairNames.forget(pairID: pairID)
        outcome.destroyed.append(pairID)
      }
      if outcome.failures == 0 {
        store.defaults.removeObject(forKey: requestedAtKey)
      }
      return outcome
    }

    /// Names an attempt's failures among the development errors.
    internal static func report(_ outcome: Outcome) {
      #if DEBUG
        if outcome.failures > 0 {
          DevErrorLog.report(
            "remote use off: \(outcome.failures) pairing(s) not destroyed, kept for the next try",
            source: .app)
        }
      #endif
    }
  }

#endif
