// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Ending a pairing the way RAPP v26.10.18 §4.6 requires: the record is
  /// revoked at the wall-clock time, and what announces the revocation to
  /// the former peer is kept for its 30 days.
  public enum RappPairRevocation {
    /// Revokes `pair` in `vault` and keeps its revocation retention.
    ///
    /// The retention is kept whatever this endpoint's role: a custodian
    /// announces it, a requester holds it until it expires. A degenerate
    /// agreement leaves none.
    public static func revoke(
      _ pair: RappPairRecord, in vault: RappDeviceVault, clock: RappPlatformClock
    ) throws {
      let pairID = pair.metadata().pairId
      if let retention = try pair.revoke(vault: vault, revokedAtMs: clock.wallMilliseconds()) {
        try vault.storeRevocationRetention(pairID: pairID, retention: retention)
      }
    }

    /// Revokes the pairing `pairID` names, when the vault still holds it.
    ///
    /// A pairing the vault no longer holds is already gone. A record the
    /// vault holds but cannot read is revoked without an announcement:
    /// no key can be derived from it.
    public static func revoke(
      pairID: Data, in vault: RappDeviceVault, clock: RappPlatformClock
    ) throws {
      let pair: RappPairRecord
      do {
        pair = try RappPairRecord.loadFromVault(pairId: pairID, vault: vault)
      } catch RappBindingError.PairNotFound {
        return
      } catch RappBindingError.InvalidInput {
        try vault.revokePair(pairID: pairID, revokedAtMilliseconds: clock.wallMilliseconds())
        return
      }
      try revoke(pair, in: vault, clock: clock)
    }

    /// The retentions still inside their announcement window at `date`,
    /// destroying the ones whose window has run out.
    public static func announcedRetentions(
      in vault: RappDeviceVault, at date: Date
    ) -> [Data] {
      guard let kept = try? vault.revocationRetentions() else { return [] }
      let now = StreamRendezvousName.unixTime(date)
      var announced: [Data] = []
      for entry in kept {
        if rappRevocationRetentionExpired(retention: entry.retention, unixTimeSeconds: now) {
          try? vault.removeRevocationRetention(pairID: entry.pairID)
        } else {
          announced.append(entry.retention)
        }
      }
      return announced
    }
  }
#endif
