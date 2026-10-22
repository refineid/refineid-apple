// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine
  extension RappDeviceVault: RappPairVault {
    /// Engine binding for ``insertPair(pairID:record:)``.
    public func insertDeviceOnly(pairId: Data, record: Data) throws {
      do {
        try insertPair(pairID: pairId, record: record)
      } catch {
        throw rappVaultError(error)
      }
    }

    /// Engine binding for ``replacePair(pairID:record:)``.
    public func replaceDeviceOnly(pairId: Data, record: Data) throws {
      do {
        try replacePair(pairID: pairId, record: record)
      } catch {
        throw rappVaultError(error)
      }
    }

    /// Engine binding for ``loadPair(pairID:)``.
    public func loadDeviceOnly(pairId: Data) throws -> Data? {
      do {
        return try loadPair(pairID: pairId)
      } catch {
        throw rappVaultError(error)
      }
    }

    /// Engine binding for ``revokePair(pairID:revokedAtMilliseconds:)``.
    public func revokeDeviceOnly(pairId: Data, revokedAtMs: UInt64) throws {
      do {
        try revokePair(pairID: pairId, revokedAtMilliseconds: revokedAtMs)
      } catch {
        throw rappVaultError(error)
      }
    }

    /// Engine binding for ``pairIsRevoked(pairID:)``.
    public func isRevoked(pairId: Data) throws -> Bool {
      do {
        return try pairIsRevoked(pairID: pairId)
      } catch {
        throw rappVaultError(error)
      }
    }
  }

  private func rappVaultError(_ error: any Error) -> RappVaultError {
    guard let failure = error as? RappDeviceVault.Failure else {
      return .Unavailable
    }
    switch failure {
    case .duplicate:
      return .IdentifierAlreadyUsed

    case .notFound:
      return .PairNotFound

    case .malformed, .unavailable:
      return .Unavailable
    }
  }
#endif

#if canImport(RappEngine)
  import RappEngine

  extension RappDeviceVault {
    /// Removes stored pairings this version can no longer read, and
    /// revokes those whose storage the peer never confirmed (RAPP v26.10.21
    /// §4.3 item 4), so the holder pairs again instead of keeping a pairing
    /// nothing can use.
    ///
    /// Only a record the engine rejects as malformed, or one left
    /// unconfirmed, goes; a keychain that cannot be read leaves everything
    /// in place. An unconfirmed record is destroyed and nobody is told
    /// (§4.6 item 3).
    @discardableResult
    public func dropUnreadablePairs() -> Int {
      guard let pairIDs = try? activePairIDs() else { return 0 }
      var dropped = 0
      for pairID in pairIDs {
        do {
          let pair = try RappPairRecord.loadFromVault(pairId: pairID, vault: self)
          guard !pair.metadata().storageConfirmed else { continue }
          if (try? RappPairRevocation.revoke(pair, in: self, clock: RappPlatformClock())) != nil {
            dropped += 1
          }
        } catch RappBindingError.InvalidInput {
          if (try? revokePair(pairID: pairID, revokedAtMilliseconds: 0)) != nil {
            dropped += 1
          }
        } catch {
          continue
        }
      }
      if dropped > 0, let selected = try? selectedPairID(),
        (try? RappPairRecord.loadFromVault(pairId: selected, vault: self)) == nil
      {
        try? clearSelectedPair()
      }
      return dropped
    }
  }
#endif
