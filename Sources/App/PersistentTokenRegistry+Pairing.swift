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
    /// close (RAPP v26.11.8 §4.6 item 2), so it pairs no phone.
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

    /// Follows `phone`, which this computer's user has just paired, over
    /// the Bluetooth advertiser `peripheral` when the pairing ran there,
    /// and shows that it connects to it until its first card status or the
    /// redial window (RAPP v26.11.8 §4.7).
    internal func followJustPaired(phone: String, peripheral: UUID?) {
      phoneJustPaired = phone
      peripheralJustPaired = peripheral
      justPairedLapse?.cancel()
      justPairedLapse = Task { @MainActor [weak self] in
        try? await Task.sleep(for: Self.redialWindow)
        guard !Task.isCancelled else { return }
        self?.connectedAfterPairing()
      }
      startAfterPairing()
    }

    /// Ends the connecting shown after a pairing.
    internal func connectedAfterPairing() {
      justPairedLapse?.cancel()
      justPairedLapse = nil
      phoneJustPaired = nil
      peripheralJustPaired = nil
    }
  }
#endif
