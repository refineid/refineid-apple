// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// The device vault as the engine sees it during one pairing write,
  /// keeping the storage failure the engine reduces to a bare
  /// `LocalStateFailure`.
  ///
  /// The engine answers every refused write with the same error, so the
  /// coordinator could not tell a full disk from any other refusal. The
  /// witness hands the engine exactly what the vault's own binding hands
  /// it, and remembers the vault failure underneath.
  internal final class RappVaultWriteWitness: RappPairVault, @unchecked Sendable {
    private let vault: RappDeviceVault
    private let lock = NSLock()
    private var refusal: (any Error)?

    /// Why the pairing ends after the engine refused to store it.
    internal var closeReason: RappPairingCoordinator.CloseReason {
      let refused = lock.withLock { refusal }
      guard let refused, StorageFailure.isOutOfSpace(refused) else {
        return .persistenceFailure
      }
      return .outOfSpace
    }

    internal init(vault: RappDeviceVault) {
      self.vault = vault
    }

    /// Runs one vault call, remembering a failure before handing the
    /// engine its binding error.
    internal func witnessing<Value>(_ call: () throws -> Value) throws -> Value {
      do {
        return try call()
      } catch {
        lock.withLock { refusal = error }
        throw rappVaultError(error)
      }
    }

    internal func insertDeviceOnly(pairId: Data, record: Data) throws {
      try witnessing { try vault.insertPair(pairID: pairId, record: record) }
    }

    internal func replaceDeviceOnly(pairId: Data, record: Data) throws {
      try witnessing { try vault.replacePair(pairID: pairId, record: record) }
    }

    internal func loadDeviceOnly(pairId: Data) throws -> Data? {
      try witnessing { try vault.loadPair(pairID: pairId) }
    }

    internal func revokeDeviceOnly(pairId: Data, revokedAtMs: UInt64) throws {
      try witnessing { try vault.revokePair(pairID: pairId, revokedAtMilliseconds: revokedAtMs) }
    }

    internal func isRevoked(pairId: Data) throws -> Bool {
      try witnessing { try vault.pairIsRevoked(pairID: pairId) }
    }
  }
#endif
