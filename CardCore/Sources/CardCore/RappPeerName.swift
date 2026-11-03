// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Keeping the peer's name in its pair record current (RAPP v26.11.2
  /// §4.3 item 4): every session carries the peer's current name, and a
  /// name that differs from the record's replaces it there.
  public enum RappPeerName {
    /// Records `name`, the name the session to the pairing `pairID` carried, where it differs from
    /// the record's.
    ///
    /// Answers whether the record holds `name` now; a store that failed keeps the old name and the
    /// session goes on.
    @discardableResult
    public static func record(
      _ name: RappDisplayName, pairID: Data, in vault: RappDeviceVault
    ) -> Bool {
      guard let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault) else {
        return false
      }
      return (try? pair.updatePeerDisplayName(vault: vault, name: name)) != nil
    }
  }
#endif
