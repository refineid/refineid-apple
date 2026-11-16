// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import Foundation
  import RappEngine
  import RappRequester

  /// The keychain vault as the forgetting reads and changes it.
  ///
  /// The record format and the revocation rules are RAPP's; the forgetting
  /// asks only what it needs, so the two parts meet here rather than inside
  /// the package, which cannot carry the vault's CardCore types.
  internal struct VaultPairingVault: PairingVault {
    /// The vault this reads and changes.
    internal let vault: RappDeviceVault

    internal func activePairIDs() throws -> [Data] {
      try vault.activePairIDs()
    }

    internal func createdAtMs(of pairID: Data) throws -> UInt64? {
      try record(pairID).metadata().createdAtMs
    }

    internal func forgottenAtMs(of pairID: Data) throws -> UInt64? {
      try record(pairID).metadata().forgottenAtMs
    }

    internal func forget(_ pairID: Data, at forgottenAtMs: UInt64) throws {
      try RappPairRevocation.forget(try record(pairID), in: vault, at: forgottenAtMs)
    }

    internal func destroy(_ pairID: Data) throws {
      try RappPairRevocation.revoke(pairID: pairID, in: vault, clock: RappPlatformClock())
    }

    /// The record `pairID` names, or the refusal the forgetting expects.
    private func record(_ pairID: Data) throws -> RappPairRecord {
      do {
        return try RappPairRecord.loadFromVault(pairId: pairID, vault: vault)
      } catch RappBindingError.PairNotFound {
        throw PairingVaultError.notFound
      } catch RappBindingError.InvalidInput {
        throw PairingVaultError.malformed
      } catch {
        throw PairingVaultError.unavailable
      }
    }
  }

#endif
