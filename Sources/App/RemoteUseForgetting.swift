// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import Foundation
  import RappEngine

  /// The holder's click turning remote use off, kept until every pairing it
  /// forgets is destroyed and the account's directory pairs none of its
  /// phones again (RAPP v26.10.22 §4.6 item 6, STPA CC-100).
  ///
  /// The click is stored with its wall-clock time before anything else
  /// happens. Every pairing created up to that time is then destroyed with
  /// its key, and its name goes once its key is gone; a pairing made after
  /// the click stays. Every same-account record of a phone this computer
  /// pairs with leaves the account's directory. What the vault or the
  /// directory does not let go stays under the stored click, which turning
  /// remote use on and the next launch finish first, so no launch restores
  /// remote use on after the holder turned it off.
  internal enum RemoteUseForgetting {
    /// What one attempt to finish the forgetting did.
    internal struct Outcome: Equatable, Sendable {
      /// The pairings destroyed.
      internal var destroyed: [Data] = []

      /// How many pairings, or listings of them, the vault refused, and the
      /// directory if it could not be reached; each is tried again by the
      /// next attempt.
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
    /// removes from `directory` every phone this computer pairs with, and
    /// clears the click once both are done; nothing without a click.
    ///
    /// Runs on any thread: quitting waits on it while the main thread
    /// answers the quit.
    internal static func finish(
      in vault: RappDeviceVault,
      store: Store,
      clock: RappPlatformClock,
      directory: any SameAccountDirectory
    ) async -> Outcome {
      guard let requestedAt = requestedAt(in: store) else { return Outcome() }
      var outcome = destroyPairings(in: vault, createdBy: requestedAt, clock: clock)
      if await !directory.removeComplementaryDevices() {
        outcome.failures += 1
      }
      if outcome.failures == 0 {
        store.defaults.removeObject(forKey: requestedAtKey)
      }
      return outcome
    }

    /// Destroys every pairing in `vault` created up to `createdBy`, with its
    /// key and then its name.
    private static func destroyPairings(
      in vault: RappDeviceVault, createdBy requestedAt: UInt64, clock: RappPlatformClock
    ) -> Outcome {
      var outcome = Outcome()
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
      return outcome
    }

    /// Names an attempt's failures among the development errors.
    internal static func report(_ outcome: Outcome) {
      #if DEBUG
        if outcome.failures > 0 {
          DevErrorLog.report(
            "remote use off: \(outcome.failures) pairing(s) or the account's directory not "
              + "settled, kept for the next try",
            source: .app)
        }
      #endif
    }
  }

#endif
