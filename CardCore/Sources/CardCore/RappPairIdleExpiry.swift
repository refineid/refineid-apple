// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Idle expiry of the pairings this device stores (RAPP v26.10.22 §4.6
  /// item 5).
  ///
  /// A pairing that has had no established session for 30 days expires on
  /// each endpoint on its own: it is stored as forgotten, keeps its key only
  /// for the `pairing_revoked` close of a later session, and nothing is sent
  /// or shown. Every check takes whether a session to the pairing is
  /// established, so a pairing in use never expires.
  public enum RappPairIdleExpiry {
    /// What one sweep of the vault did.
    public struct Sweep: Equatable, Sendable {
      /// The pairings that expired, each stored as forgotten.
      public var expired: [Data] = []

      /// How many pairings the sweep could not read or store; each is
      /// swept again whole by the next sweep.
      public var failures = 0
    }

    /// Sweeps every active pairing in `vault` at `nowMilliseconds`,
    /// milliseconds since the Unix epoch.
    ///
    /// `established` names the pairings a session is established to now:
    /// their time is recorded instead. A pairing that expires leaves the
    /// selection and its name is forgotten. A pairing not yet confirmed,
    /// or already forgotten, is left as it is.
    public static func sweep(
      in vault: RappDeviceVault, nowMilliseconds: UInt64, established: Set<Data>
    ) -> Sweep {
      var sweep = Sweep()
      guard let pairIDs = try? vault.activePairIDs() else {
        sweep.failures += 1
        return sweep
      }
      for pairID in pairIDs {
        let outcome: RappSweepOutcome
        do {
          outcome = try RappPairRecord.loadFromVault(pairId: pairID, vault: vault).sweep(
            vault: vault, nowMs: nowMilliseconds,
            sessionEstablished: established.contains(pairID))
        } catch RappBindingError.StorageUnconfirmed {
          continue
        } catch {
          sweep.failures += 1
          continue
        }
        guard outcome == .expired else { continue }
        if (try? vault.selectedPairID()) == pairID {
          try? vault.clearSelectedPair()
        }
        RappPairNames.forget(pairID: pairID)
        sweep.expired.append(pairID)
      }
      return sweep
    }

    /// Records that a session to `pairID` is established at
    /// `nowMilliseconds`, as the session is established and as it ends;
    /// false when the vault could not store it.
    @discardableResult
    public static func recordSession(
      pairID: Data, in vault: RappDeviceVault, nowMilliseconds: UInt64
    ) -> Bool {
      do {
        _ = try RappPairRecord.loadFromVault(pairId: pairID, vault: vault).sweep(
          vault: vault, nowMs: nowMilliseconds, sessionEstablished: true)
        return true
      } catch RappBindingError.PairNotFound {
        return true
      } catch {
        return false
      }
    }

    /// Whether `vault` holds a pairing that serves: confirmed, and not
    /// forgotten.
    public static func holdsActivePairing(_ vault: RappDeviceVault) -> Bool {
      ((try? vault.activePairIDs()) ?? []).contains { pairID in
        guard let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault) else {
          return false
        }
        let metadata = pair.metadata()
        return metadata.storageConfirmed && metadata.forgottenAtMs == nil
      }
    }
  }
#endif
