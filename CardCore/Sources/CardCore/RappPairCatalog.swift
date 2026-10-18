// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine
  /// Device-local view of active RAPP pair records. Pair private material
  /// never leaves Rust.
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
    public func activePairs() throws -> [RappPairingCoordinator.PairSummary] {
      var seen = Set<Data>()
      return try vault.activePairIDs()
        .sorted { $0.lexicographicallyPrecedes($1) }
        .compactMap { pairID in
          guard seen.insert(pairID).inserted else { return nil }
          guard let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault) else {
            return nil
          }
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

    /// Deletes the pair record and keeps what announces the revocation
    /// (RAPP v26.10.18 §4.6).
    ///
    /// Same-account auto-pairing may recreate it.
    public func revoke(pairID: Data) throws {
      let pair = try load(pairID: pairID)
      try RappPairRevocation.revoke(pair, in: vault, clock: clock)
      if try vault.selectedPairID() == pairID {
        try vault.clearSelectedPair()
      }
    }
  }
#endif
