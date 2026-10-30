// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(CryptoTokenKit) && canImport(RappEngine)
  import CryptoTokenKit
  import Foundation
  import RappEngine

  /// Resolves the active smart card identity source following hardware-first arbitration.
  ///
  /// Priority Order:
  /// 1. Physical Reader: If a reader is connected with a card present.
  /// 2. Remote RAPP Card: If no physical card is detected, fallback to the paired phone.
  public enum CardSourceArbitrator {
    // MARK: Types

    /// The active identity source selected by arbitration.
    public enum Source: Equatable, Sendable {
      /// Physical smartcard reader with its slot name.
      case physicalReader(slotName: String)
      /// Remote RAPP pair identifier.
      case remoteRappPair(pairID: Data)
    }

    // MARK: Arbitration

    /// Determines which card source should handle smartcard operations.
    public static func resolveActiveSource(
      vault: RappDeviceVault,
      slotManager: TKSmartCardSlotManager? = .default
    ) async -> Source? {
      // 1. Check physical reader
      if let slotManager {
        for name in slotManager.slotNames {
          if let slot = await slotManager.getSlot(withName: name), slot.state == .validCard {
            return .physicalReader(slotName: name)
          }
        }
      }

      // 2. Fallback to active RAPP pairing
      if let selectedID = try? vault.selectedPairID(),
        (try? vault.loadPair(pairID: selectedID)) != nil
      {
        return .remoteRappPair(pairID: selectedID)
      }

      if let firstActiveID = try? vault.activePairIDs().first {
        return .remoteRappPair(pairID: firstActiveID)
      }

      return nil
    }
  }
#endif
