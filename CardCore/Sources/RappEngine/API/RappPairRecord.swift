// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A stored pairing.
///
/// The record holds the pairing's keys, so it is never handed out as bytes
/// except through the vault the caller owns.
public final class RappPairRecord: @unchecked Sendable {
  internal let record: PairRecord

  internal init(record: PairRecord) {
    self.record = record
  }

  /// Reads the pairing the identifier names.
  ///
  /// - Throws: ``RappBindingError/PairNotFound`` when no stored
  ///   pairing carries the identifier, and
  ///   ``RappBindingError/LocalStateFailure`` when storage refused.
  public static func loadFromVault(pairId: Data, vault: RappPairVault) throws -> RappPairRecord {
    let stored: Data?
    do {
      stored = try vault.loadDeviceOnly(pairId: pairId)
    } catch {
      throw RappBindingError.LocalStateFailure
    }
    guard let stored else {
      throw RappBindingError.PairNotFound
    }
    do {
      return RappPairRecord(record: try PairRecord.decode(stored))
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

  /// Returns the raw serialized bytes of this pair record.
  public func encodedBytes() throws -> Data {
    do {
      return try record.encoded()
    } catch {
      throw RappBindingError.InvalidInput
    }
  }

  /// What the pairing says about itself, without its keys.
  public func metadata() -> RappPairMetadata {
    RappPairMetadata(
      pairId: record.pairIdentifier,
      role: RappEndpointRole(record.role),
      profiles: record.profiles.map(\.rawValue),
      transportProfile: record.transport.profile,
      candidateId: record.transport.candidateIdentifier,
      createdAtMs: record.createdAtMilliseconds,
      storageConfirmed: record.storageConfirmed)
  }

  /// Stores the confirmed pairing over the unconfirmed record written
  /// before the peer's `pairing.stored` arrived (RAPP v26.10.18 §4.3 item
  /// 4).
  ///
  /// - Throws: ``RappBindingError/StorageUnconfirmed`` for a record that is
  ///   not confirmed, and ``RappBindingError/LocalStateFailure`` when
  ///   storage refused the write.
  public func replaceDeviceOnly(vault: RappPairVault) throws {
    guard record.storageConfirmed else { throw RappBindingError.StorageUnconfirmed }
    let encoded: Data
    do {
      encoded = try record.encoded()
    } catch {
      throw RappBindingError.InvalidInput
    }
    do {
      try vault.replaceDeviceOnly(pairId: record.pairIdentifier, record: encoded)
    } catch {
      throw RappBindingError.LocalStateFailure
    }
  }

  /// Writes the pairing where it must never leave this device.
  ///
  /// - Throws: ``RappBindingError/LocalStateFailure`` when storage
  ///   refused the write.
  public func persistDeviceOnly(vault: RappPairVault) throws {
    let encoded: Data
    do {
      encoded = try record.encoded()
    } catch {
      throw RappBindingError.InvalidInput
    }
    do {
      try vault.insertDeviceOnly(pairId: record.pairIdentifier, record: encoded)
    } catch {
      throw RappBindingError.LocalStateFailure
    }
  }

  /// Ends the pairing and destroys its keys, at `revokedAtMs` milliseconds
  /// since the Unix epoch.
  ///
  /// The encoded revocation retention comes back for the caller to keep
  /// (RAPP v26.10.18 §4.6 item 2): a custodian announces it for 30 days
  /// through ``rappSessionRecord(candidates:retentions:instance:unixTimeSeconds:)``.
  /// It holds the revocation key and is the caller's to protect; a
  /// degenerate agreement yields none.
  ///
  /// - Throws: ``RappBindingError/LocalStateFailure`` when storage
  ///   refused.
  public func revoke(vault: RappPairVault, revokedAtMs: UInt64) throws -> Data? {
    let retention = RevocationRetention(record: record, revokedAtMilliseconds: revokedAtMs)
    do {
      try vault.revokeDeviceOnly(pairId: record.pairIdentifier, revokedAtMs: revokedAtMs)
    } catch {
      throw RappBindingError.LocalStateFailure
    }
    return try? retention?.encoded()
  }
}
