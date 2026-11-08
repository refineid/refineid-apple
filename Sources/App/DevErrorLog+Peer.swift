// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG
  import CardCore
  import Foundation
  import RappEngine

  /// Names the paired device a failed session belonged to, so that the
  /// development error strip says who was talking.
  extension DevErrorLog {
    /// The text for a pairing whose record is gone or unreadable.
    private static let unknownPeer = "unknown pairing"

    /// The display name the pair record keeps for its peer (RAPP v26.11.8
    /// §4.3 items 3 and 4), or a placeholder when the record cannot be
    /// read.
    ///
    /// The name is the device's label, never the holder's: a computer's
    /// host name or a phone's device name.
    internal static func peerName(pairID: Data?, vault: RappDeviceVault) -> String {
      guard
        let pairID,
        let record = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault)
      else {
        return unknownPeer
      }
      return record.metadata().peerDisplayName
    }
  }
#endif
