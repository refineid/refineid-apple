// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A stored pairing.
///
/// The record holds the pairing's keys, so it is never handed out as bytes
/// except through the vault the caller owns. Once revoked it holds them no
/// more: nothing in this process can use the key afterwards (RAPP v26.10.22
/// §4.6 items 3 and 4).
public final class RappPairRecord: @unchecked Sendable {
  private let lock = NSLock()
  /// The pairing with its keys; nil once the vault confirmed the revocation.
  private var stored: PairRecord?
  /// What the pairing says about itself, kept after its keys are gone.
  private var summary: RappPairMetadata

  /// The record as it stands now.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` once the pairing was revoked.
  internal var record: PairRecord {
    get throws {
      try locked {
        guard let stored else { throw RappBindingError.WrongPhase }
        return stored
      }
    }
  }

  internal init(record: PairRecord) {
    self.stored = record
    self.summary = Self.summary(of: record)
  }

  /// Reads the pairing the identifier names.
  ///
  /// - Throws: ``RappBindingError/PairNotFound`` when no stored
  ///   pairing carries the identifier, and
  ///   ``RappBindingError/LocalStateFailure`` when storage refused.
  public static func loadFromVault(pairId: Data, vault: RappPairVault) throws -> RappPairRecord {
    let loaded: Data?
    do {
      loaded = try vault.loadDeviceOnly(pairId: pairId)
    } catch {
      throw RappBindingError.LocalStateFailure
    }
    guard let loaded else {
      throw RappBindingError.PairNotFound
    }
    do {
      return RappPairRecord(record: try PairRecord.decode(loaded))
    } catch {
      throw RappBindingError.InvalidInput
    }
  }

  /// Decodes a pair record from its raw serialized bytes.
  public static func decode(from data: Data) throws -> RappPairRecord {
    do {
      return RappPairRecord(record: try PairRecord.decode(data))
    } catch {
      throw RappBindingError.InvalidInput
    }
  }

  /// The record's description, without its keys.
  private static func summary(of record: PairRecord) -> RappPairMetadata {
    RappPairMetadata(
      pairId: record.pairIdentifier,
      role: RappEndpointRole(record.role),
      profiles: record.profiles.map(\.rawValue),
      transportProfile: record.transport.profile,
      candidateId: record.transport.candidateIdentifier,
      createdAtMs: record.createdAtMilliseconds,
      storageConfirmed: record.storageConfirmed,
      forgottenAtMs: record.forgottenAtMilliseconds)
  }

  /// Revokes `record` in the vault, which destroys its secret before
  /// returning.
  private static func destroy(_ record: PairRecord, in vault: RappPairVault, at time: UInt64)
    throws
  {
    do {
      try vault.revokeDeviceOnly(pairId: record.pairIdentifier, revokedAtMs: time)
    } catch {
      throw RappBindingError.LocalStateFailure
    }
  }

  /// Returns the raw serialized bytes of this pair record.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` once the pairing was revoked.
  public func encodedBytes() throws -> Data {
    let current = try record
    do {
      return try current.encoded()
    } catch {
      throw RappBindingError.InvalidInput
    }
  }

  /// What the pairing says about itself, without its keys; a revoked
  /// pairing still describes itself as it last stood.
  public func metadata() -> RappPairMetadata {
    locked { summary }
  }

  /// Stores the confirmed pairing over the unconfirmed record written
  /// before the peer's `pairing.stored` arrived (RAPP v26.10.22 §4.3 item
  /// 4).
  ///
  /// - Throws: ``RappBindingError/StorageUnconfirmed`` for a record that is
  ///   not confirmed, and ``RappBindingError/LocalStateFailure`` when
  ///   storage refused the write.
  public func replaceDeviceOnly(vault: RappPairVault) throws {
    let current = try record
    guard current.storageConfirmed else { throw RappBindingError.StorageUnconfirmed }
    let encoded: Data
    do {
      encoded = try current.encoded()
    } catch {
      throw RappBindingError.InvalidInput
    }
    do {
      try vault.replaceDeviceOnly(pairId: current.pairIdentifier, record: encoded)
    } catch {
      throw RappBindingError.LocalStateFailure
    }
  }

  /// Writes the pairing where it must never leave this device.
  ///
  /// - Throws: ``RappBindingError/LocalStateFailure`` when storage
  ///   refused the write.
  public func persistDeviceOnly(vault: RappPairVault) throws {
    let current = try record
    let encoded: Data
    do {
      encoded = try current.encoded()
    } catch {
      throw RappBindingError.InvalidInput
    }
    do {
      try vault.insertDeviceOnly(pairId: current.pairIdentifier, record: encoded)
    } catch {
      throw RappBindingError.LocalStateFailure
    }
  }

  /// The local user forgets the pairing while no session to the peer is
  /// open (RAPP v26.10.22 §4.6).
  ///
  /// A confirmed record is stored as forgotten and keeps its key only to
  /// deliver the `pairing_revoked` close on the next session; an unconfirmed
  /// one is destroyed at once, here and in the vault, and nobody is told.
  /// With a session open, close it with reason `pairingRevoked` and call
  /// ``revoke(vault:revokedAtMs:)`` instead. `forgottenAtMs` is milliseconds
  /// since the Unix epoch.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` for a revoked pairing, and
  ///   ``RappBindingError/LocalStateFailure`` when storage refused.
  public func forget(vault: RappPairVault, forgottenAtMs: UInt64) throws -> RappForgetOutcome {
    try locked {
      guard let current = stored else { throw RappBindingError.WrongPhase }
      guard current.storageConfirmed else {
        try Self.destroy(current, in: vault, at: forgottenAtMs)
        stored = nil
        return .destroyed
      }
      let forgotten = current.forgotten(at: forgottenAtMs)
      do {
        try vault.replaceDeviceOnly(pairId: forgotten.pairIdentifier, record: forgotten.encoded())
      } catch {
        throw RappBindingError.LocalStateFailure
      }
      stored = forgotten
      summary = Self.summary(of: forgotten)
      return .noticePending
    }
  }

  /// Whether a forgotten record kept its key for 30 days without a session
  /// to deliver the close (§4.6 item 3).
  ///
  /// Destroy it then with ``revoke(vault:revokedAtMs:)``; a revoked pairing
  /// has nothing left to expire.
  public func revocationNoticeExpired(nowMs: UInt64) -> Bool {
    locked { stored?.revocationNoticeExpired(nowMilliseconds: nowMs) ?? false }
  }

  /// Ends the pairing and destroys its keys, at `revokedAtMs` milliseconds
  /// since the Unix epoch (§4.6 items 3 and 4): first in the vault, then
  /// here, so nothing in this process can use the key afterwards.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` for a pairing already revoked,
  ///   and ``RappBindingError/LocalStateFailure`` when storage refused; the
  ///   record then keeps its keys for another attempt.
  public func revoke(vault: RappPairVault, revokedAtMs: UInt64) throws {
    try locked {
      guard let current = stored else { throw RappBindingError.WrongPhase }
      try Self.destroy(current, in: vault, at: revokedAtMs)
      stored = nil
    }
  }

  private func locked<Value>(_ body: () throws -> Value) rethrows -> Value {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}
