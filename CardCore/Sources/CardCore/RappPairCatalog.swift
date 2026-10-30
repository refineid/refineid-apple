// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine
  /// Device-local view of active RAPP pair records. Pair private material
  /// never leaves the engine.
  public actor RappPairCatalog {
    /// Why a catalog read was refused.
    public enum CatalogError: Error, Sendable {
      case duplicatePairIdentifier
    }

    private let vault: RappDeviceVault
    private let clock: RappPlatformClock

    /// Builds a catalog over the vault's pair records.
    public init(
      vault: RappDeviceVault,
      clock: RappPlatformClock = RappPlatformClock()
    ) {
      self.vault = vault
      self.clock = clock
    }

    /// Lists every active pair as a summary, in stable identifier order,
    /// refusing a vault that repeats a pair identifier.
    ///
    /// A pairing this endpoint forgot serves nothing and is not listed (RAPP
    /// v26.10.29 §4.6).
    public func activePairs() throws -> [RappPairingCoordinator.PairSummary] {
      var seen = Set<Data>()
      return try vault.activePairIDs()
        .sorted { $0.lexicographicallyPrecedes($1) }
        .compactMap { pairID in
          guard seen.insert(pairID).inserted else { return nil }
          guard let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault),
            pair.metadata().forgottenAtMs == nil
          else { return nil }
          return RappPairingCoordinator.PairSummary(pair.metadata())
        }
    }

    /// Loads one pair record from the vault by identifier.
    public func load(pairID: Data) throws -> RappPairRecord {
      try RappPairRecord.loadFromVault(pairId: pairID, vault: vault)
    }

    /// The summary of the selected pair, or nil when none is selected.
    public func selectedPair() throws -> RappPairingCoordinator.PairSummary? {
      guard let pairID = try vault.selectedPairID() else { return nil }
      guard let pair = try? load(pairID: pairID) else { return nil }
      return RappPairingCoordinator.PairSummary(pair.metadata())
    }

    /// Marks one pair as selected after proving it loads.
    public func select(pairID: Data) throws {
      _ = try load(pairID: pairID)
      try vault.selectPair(pairID: pairID)
    }

    /// Clears the selection without touching the pair itself.
    public func clearSelection() throws {
      try vault.clearSelectedPair()
    }

    /// Forgets the pairing while no session to its peer is open: it serves
    /// nothing from now on and keeps its key only to tell the peer on the
    /// next session (RAPP v26.10.29 §4.6 item 2).
    @discardableResult
    public func forget(pairID: Data) throws -> RappForgetOutcome {
      try RappPairRevocation.forget(try load(pairID: pairID), in: vault, clock: clock)
    }

    /// Destroys the pair record and its key now.
    public func revoke(pairID: Data) throws {
      try RappPairRevocation.revoke(pairID: pairID, in: vault, clock: clock)
    }
  }
#endif
