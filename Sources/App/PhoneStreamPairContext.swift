// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation
  import RappEngine

  /// One active pairing the session listener serves.
  internal struct PhoneStreamPairContext {
    /// The pairing identifier in hex, for bookkeeping only.
    internal let key: String

    internal let pairRecord: RappPairRecord

    internal static func resolveAll(vault: RappDeviceVault) -> [Self] {
      guard let activeIDs = try? vault.activePairIDs(), !activeIDs.isEmpty else { return [] }
      return activeIDs.compactMap { pairID in
        guard let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault) else {
          return nil
        }
        return Self(key: pairID.map { String(format: "%02x", $0) }.joined(), pairRecord: pair)
      }
    }

    /// This pairing's hint for `make`, ranked by when it was last used.
    internal func candidate(
      at date: Date, hint make: (RappPairRecord, UInt64) throws -> Data
    ) -> RappAnnouncementCandidate? {
      guard let hint = try? make(pairRecord, StreamRendezvousName.unixTime(date)) else {
        return nil
      }
      let metadata = pairRecord.metadata()
      return RappAnnouncementCandidate(
        hint: hint,
        lastUsedMs: PairLastUse.milliseconds(pairID: metadata.pairId) ?? metadata.createdAtMs)
    }
  }
#endif
