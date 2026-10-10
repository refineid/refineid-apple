// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// The active pairings at one moment, or the fact that they could not be read.
  internal enum RappPairingSnapshot: Equatable {
    case pairs(Set<Data>)
    case unreadable

    /// The active pairings in `vault` now.
    internal init(vault: RappDeviceVault) {
      if let ids = try? vault.activePairIDs() {
        self = .pairs(Set(ids))
      } else {
        self = .unreadable
      }
    }

    /// Whether `later` reports other pairings; a snapshot that could not be
    /// read on either side counts as a change.
    internal func differs(from later: Self) -> Bool {
      guard case .pairs(let before) = self, case .pairs(let after) = later else { return true }
      return before != after
    }
  }
#endif
