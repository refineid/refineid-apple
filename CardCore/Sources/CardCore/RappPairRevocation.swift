// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Ending a pairing the way RAPP v26.11.2 §4.6 requires.
  ///
  /// With a session open the endpoint closes it with `pairing_revoked`,
  /// waits for the echo within its bound, and revokes. Without one the
  /// record is marked forgotten: it serves nothing and keeps its key only to
  /// deliver that close, on a custodian on the next session for 30 days,
  /// on a requester in its revocation backlog until the custodian echoes
  /// the close or the pairing's idle expiry would have passed.
  public enum RappPairRevocation {
    /// Forgets `pair` now: it leaves the selection, serves nothing, and keeps
    /// its key only for the close.
    @discardableResult
    public static func forget(
      _ pair: RappPairRecord, in vault: RappDeviceVault, clock: RappPlatformClock
    ) throws -> RappForgetOutcome {
      try forget(pair, in: vault, at: clock.wallMilliseconds())
    }

    /// Forgets `pair` as its user did at `forgottenAtMs`, milliseconds since
    /// the Unix epoch.
    @discardableResult
    public static func forget(
      _ pair: RappPairRecord, in vault: RappDeviceVault, at forgottenAtMs: UInt64
    ) throws -> RappForgetOutcome {
      let outcome = try pair.forget(vault: vault, forgottenAtMs: forgottenAtMs)
      try clearSelection(of: pair.metadata().pairId, in: vault)
      return outcome
    }

    /// Destroys `pair` and its key now: its close was delivered, the peer
    /// revoked it, its 30 days ran out, or it was never confirmed.
    public static func revoke(
      _ pair: RappPairRecord, in vault: RappDeviceVault, clock: RappPlatformClock
    ) throws {
      try pair.revoke(vault: vault, revokedAtMs: clock.wallMilliseconds())
      try clearSelection(of: pair.metadata().pairId, in: vault)
    }

    /// Destroys the pairing `pairID` names, when the vault still holds it.
    ///
    /// A pairing the vault no longer holds is already gone; a record the
    /// vault holds but cannot read is destroyed all the same.
    public static func revoke(
      pairID: Data, in vault: RappDeviceVault, clock: RappPlatformClock
    ) throws {
      do {
        try revoke(
          try RappPairRecord.loadFromVault(pairId: pairID, vault: vault), in: vault, clock: clock)
      } catch RappBindingError.PairNotFound {
        return
      } catch RappBindingError.InvalidInput {
        try vault.revokePair(pairID: pairID, revokedAtMilliseconds: clock.wallMilliseconds())
        try clearSelection(of: pairID, in: vault)
      }
    }

    /// Destroys every forgotten record whose time ran out without its close
    /// delivered: 30 days after the forget on a custodian, and on a
    /// requester 30 days after the pairing's last established session
    /// (§4.6 items 3 and 6).
    public static func expireRevocationNotices(in vault: RappDeviceVault, clock: RappPlatformClock)
    {
      guard let pairIDs = try? vault.activePairIDs() else { return }
      let now = clock.wallMilliseconds()
      for pairID in pairIDs {
        guard let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault),
          pair.revocationNoticeExpired(nowMs: now)
        else { continue }
        try? revoke(pair, in: vault, clock: clock)
      }
    }

    private static func clearSelection(of pairID: Data, in vault: RappDeviceVault) throws {
      if try vault.selectedPairID() == pairID {
        try vault.clearSelectedPair()
      }
    }
  }
#endif
