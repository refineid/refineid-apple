// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import Foundation
  import os
  import RappEngine

  /// The holder's click turning remote use off, kept until every pairing it
  /// forgets is destroyed and the account's directory pairs none of their
  /// phones again (RAPP v26.10.22 §4.6 item 6, STPA CC-100).
  ///
  /// The click is stored with its wall-clock time and the pairings it
  /// forgets before anything else happens. Those pairings are then
  /// destroyed with their keys, and each name goes once its key is gone; a
  /// pairing made after the click stays. The same-account records of
  /// exactly those pairings' phones leave the account's directory, so a
  /// phone paired only with another computer stays. What the vault or the
  /// directory does not let go stays under the stored click, which turning
  /// remote use on and the next launch finish first, so no launch restores
  /// remote use on after the holder turned it off. A click is cleared only
  /// by the attempt that finished it, never one stored after it.
  internal enum RemoteUseForgetting {
    /// What one attempt to finish the forgetting did.
    internal struct Outcome: Equatable, Sendable {
      /// The pairings destroyed.
      internal var destroyed: [Data] = []

      /// How many pairings, or listings of them, the vault refused, and the
      /// directory if it still holds a phone; each is tried again by the
      /// next attempt.
      internal var failures = 0
    }

    /// The stored click: when it was made, and the pairings it forgets.
    internal struct Request: Codable, Equatable, Sendable {
      /// When the holder clicked, in milliseconds since the Unix epoch.
      internal var clickedAtMs: UInt64

      /// The pairings the click forgets, listed before any is destroyed.
      internal var pairIDs: [Data]

      /// Whether the vault could not be listed when the click was stored:
      /// the next attempt lists the pairings made up to the click before it
      /// destroys any.
      internal var needsListing: Bool
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

    /// The defaults key the click is stored under.
    internal static let requestKey = "fi.refineid.rapp.remote-use-off-request"

    /// Serialises each read, compare and write of the stored click.
    private static let lock = OSAllocatedUnfairLock()

    /// The click whose forgetting is not finished; nil when none is
    /// pending.
    internal static func pending(in store: Store) -> Request? {
      lock.withLock { read(store) }
    }

    /// Stores the holder's click at `clickedAtMs`, forgetting the pairings
    /// `vault` holds, before the forgetting starts.
    internal static func request(
      at clickedAtMs: UInt64, listing vault: RappDeviceVault, in store: Store
    ) {
      do {
        request(
          at: clickedAtMs, forgetting: try vault.activePairIDs(), listed: true, in: store)
      } catch {
        request(at: clickedAtMs, forgetting: [], listed: false, in: store)
      }
    }

    /// Stores the holder's click at `clickedAtMs` before the forgetting
    /// starts.
    ///
    /// It forgets `pairIDs`, and, when the vault was not `listed`, whatever
    /// it holds from up to the click. A click still pending is covered: its
    /// pairings stay listed, and the later time counts.
    internal static func request(
      at clickedAtMs: UInt64, forgetting pairIDs: [Data], listed: Bool, in store: Store
    ) {
      lock.withLock {
        let earlier = read(store)
        write(
          Request(
            clickedAtMs: max(earlier?.clickedAtMs ?? clickedAtMs, clickedAtMs),
            pairIDs: merged((earlier?.pairIDs ?? []) + pairIDs),
            needsListing: !listed || earlier?.needsListing == true),
          to: store)
      }
    }

    /// Destroys the pairings the pending click forgets, removes their
    /// phones from `directory`, and clears that click once both are done;
    /// nothing without a click.
    ///
    /// Runs on any thread: quitting waits on it while the main thread
    /// answers the quit. A click stored while it ran stays for the next
    /// attempt.
    internal static func finish(
      in vault: RappDeviceVault,
      store: Store,
      clock: RappPlatformClock,
      directory: any SameAccountDirectory
    ) async -> Outcome {
      guard var request = pending(in: store) else { return Outcome() }
      if request.needsListing {
        let listed: [Data]
        do {
          listed = try listPairings(in: vault, madeBy: request.clickedAtMs)
        } catch {
          return Outcome(destroyed: [], failures: 1)
        }
        var updated = request
        updated.pairIDs = merged(request.pairIDs + listed)
        updated.needsListing = false
        guard replace(request, with: updated, in: store) else {
          return Outcome()
        }
        request = updated
      }
      var outcome = destroy(request.pairIDs, in: vault, clock: clock)
      if await !directory.removeDevices(pairedThrough: Set(request.pairIDs)) {
        outcome.failures += 1
      }
      if outcome.failures == 0 {
        clear(request, in: store)
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

    /// `pairIDs` once each, in a stable order.
    private static func merged(_ pairIDs: [Data]) -> [Data] {
      Array(Set(pairIDs)).sorted { first, second in first.lexicographicallyPrecedes(second) }
    }

    /// The pairings `vault` holds that were made up to `madeBy`.
    ///
    /// - Throws: What the vault throws when it cannot be listed.
    private static func listPairings(in vault: RappDeviceVault, madeBy clickedAtMs: UInt64)
      throws -> [Data]
    {
      try vault.activePairIDs().filter { pairID in
        let created = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault)
          .metadata().createdAtMs
        return (created ?? clickedAtMs) <= clickedAtMs
      }
    }

    /// Destroys every pairing `pairIDs` names that `vault` still holds,
    /// with its key and then its name.
    private static func destroy(
      _ pairIDs: [Data], in vault: RappDeviceVault, clock: RappPlatformClock
    ) -> Outcome {
      var outcome = Outcome()
      let held = Set((try? vault.activePairIDs()) ?? pairIDs)
      for pairID in pairIDs where held.contains(pairID) {
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

    /// Writes `updated` over `request` while it is still the stored click;
    /// false when another was stored meanwhile.
    private static func replace(_ request: Request, with updated: Request, in store: Store)
      -> Bool
    {
      lock.withLock {
        guard read(store) == request else { return false }
        write(updated, to: store)
        return true
      }
    }

    /// Clears `request` while it is still the stored click.
    private static func clear(_ request: Request, in store: Store) {
      lock.withLock {
        guard read(store) == request else { return }
        store.defaults.removeObject(forKey: requestKey)
      }
    }

    private static func read(_ store: Store) -> Request? {
      guard let data = store.defaults.data(forKey: requestKey) else { return nil }
      return try? JSONDecoder().decode(Request.self, from: data)
    }

    private static func write(_ request: Request, to store: Store) {
      guard let data = try? JSONEncoder().encode(request) else { return }
      store.defaults.set(data, forKey: requestKey)
    }
  }

#endif
