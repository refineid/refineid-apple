// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RappEngine

/// A pair vault in memory, recording what the engine asked of it.
internal final class MemoryPairVault: RappPairVault, @unchecked Sendable {
  private let lock = NSLock()
  private var records: [Data: Data] = [:]
  private var revoked: Set<Data> = []

  /// The stored record under `pairId`, if any.
  internal func stored(_ pairId: Data) -> Data? {
    lock.withLock { records[pairId] }
  }

  /// Whether `pairId` was revoked.
  internal func wasRevoked(_ pairId: Data) -> Bool {
    lock.withLock { revoked.contains(pairId) }
  }

  internal func insertDeviceOnly(pairId: Data, record: Data) throws {
    try lock.withLock {
      guard records[pairId] == nil, !revoked.contains(pairId) else {
        throw RappVaultError.IdentifierAlreadyUsed
      }
      records[pairId] = record
    }
  }

  internal func replaceDeviceOnly(pairId: Data, record: Data) throws {
    try lock.withLock {
      guard records[pairId] != nil else { throw RappVaultError.PairNotFound }
      records[pairId] = record
    }
  }

  internal func loadDeviceOnly(pairId: Data) -> Data? {
    lock.withLock { records[pairId] }
  }

  internal func revokeDeviceOnly(pairId: Data, revokedAtMs _: UInt64) throws {
    try lock.withLock {
      guard records.removeValue(forKey: pairId) != nil else { throw RappVaultError.PairNotFound }
      revoked.insert(pairId)
    }
  }

  internal func isRevoked(pairId: Data) -> Bool {
    lock.withLock { revoked.contains(pairId) }
  }
}
