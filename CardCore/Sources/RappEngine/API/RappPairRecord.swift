// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A stored pairing.
///
/// The record holds the pairing's keys, so it is never handed out as bytes
/// except through the vault the caller owns.
public final class RappPairRecord: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: PairRecord

  /// The record as it stands now.
  internal var record: PairRecord {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }

  internal init(record: PairRecord) {
    self.stored = record
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
    let current = record
    return RappPairMetadata(
      pairId: current.pairIdentifier,
      role: RappEndpointRole(current.role),
      profiles: current.profiles.map(\.rawValue),
      transportProfile: current.transport.profile,
      candidateId: current.transport.candidateIdentifier,
      createdAtMs: current.createdAtMilliseconds,
      storageConfirmed: current.storageConfirmed,
      forgottenAtMs: current.forgottenAtMilliseconds)
  }

  /// Stores the confirmed pairing over the unconfirmed record written
  /// before the peer's `pairing.stored` arrived (RAPP v26.10.21 §4.3 item
  /// 4).
  ///
  /// - Throws: ``RappBindingError/StorageUnconfirmed`` for a record that is
  ///   not confirmed, and ``RappBindingError/LocalStateFailure`` when
  ///   storage refused the write.
  public func replaceDeviceOnly(vault: RappPairVault) throws {
    let current = record
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
    let current = record
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
  /// open (RAPP v26.10.21 §4.6).
  ///
  /// A confirmed record is stored as forgotten and keeps its key only to
  /// deliver the `pairing_revoked` close on the next session; an unconfirmed
  /// one is destroyed at once and nobody is told. With a session open, close
  /// it with reason `pairingRevoked` and call ``revoke(vault:revokedAtMs:)``
  /// instead. `forgottenAtMs` is milliseconds since the Unix epoch.
  ///
  /// - Throws: ``RappBindingError/LocalStateFailure`` when storage refused.
  public func forget(vault: RappPairVault, forgottenAtMs: UInt64) throws -> RappForgetOutcome {
    try locked {
      guard stored.storageConfirmed else {
        do {
          try vault.revokeDeviceOnly(pairId: stored.pairIdentifier, revokedAtMs: forgottenAtMs)
        } catch {
          throw RappBindingError.LocalStateFailure
        }
        return .destroyed
      }
      let forgotten = stored.forgotten(at: forgottenAtMs)
      do {
        try vault.replaceDeviceOnly(pairId: forgotten.pairIdentifier, record: forgotten.encoded())
      } catch {
        throw RappBindingError.LocalStateFailure
      }
      stored = forgotten
      return .noticePending
    }
  }

  /// Whether a forgotten record kept its key for 30 days without a session
  /// to deliver the close (§4.6 item 3); destroy it then with
  /// ``revoke(vault:revokedAtMs:)``.
  public func revocationNoticeExpired(nowMs: UInt64) -> Bool {
    record.revocationNoticeExpired(nowMilliseconds: nowMs)
  }

  /// Ends the pairing and destroys its keys, at `revokedAtMs` milliseconds
  /// since the Unix epoch (§4.6 items 3 and 4).
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

  private func locked<Value>(_ body: () throws -> Value) rethrows -> Value {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}
