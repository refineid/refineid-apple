// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)
  import CardCore
  import Foundation
  import RappEngine

  extension PersistentTokenRegistry {
    /// The paired phone's pairing in `vault`: the chosen usable pairing,
    /// else the newest usable one; nil while no pairing is usable.
    ///
    /// A forgotten pairing serves nothing and stays only to deliver its
    /// close (RAPP v26.10.29 §4.6 item 2), so it pairs no phone.
    internal static func pairedPhoneID(in vault: RappDeviceVault) -> Data? {
      let usable = ((try? vault.activePairIDs()) ?? [])
        .compactMap { try? RappPairRecord.loadFromVault(pairId: $0, vault: vault).metadata() }
        .filter { $0.forgottenAtMs == nil }
      if let selected = try? vault.selectedPairID(),
        usable.contains(where: { $0.pairId == selected })
      {
        return selected
      }
      return usable.max { $0.createdAtMs < $1.createdAtMs }?.pairId
    }

    /// Reads which phone is paired, for the identity row.
    internal func refreshPairing() {
      refreshPairing(in: RappDeviceVault())
    }
  }
#endif
