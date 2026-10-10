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
      createdAtMs: record.createdAtMilliseconds)
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

  /// Ends the pairing and destroys its keys.
  ///
  /// - Throws: ``RappBindingError/LocalStateFailure`` when storage
  ///   refused.
  public func revoke(vault: RappPairVault, revokedAtMs: UInt64) throws {
    do {
      try vault.revokeDeviceOnly(pairId: record.pairIdentifier, revokedAtMs: revokedAtMs)
    } catch {
      throw RappBindingError.LocalStateFailure
    }
  }
}
