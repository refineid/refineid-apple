// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import SwiftUI

/// The clock a revocation is stamped by.
private let clock = RappPlatformClock()

extension RappPairingModel {
  /// Posted when the set of active pairings changes.
  internal static let pairingsDidChangeNotification =
    RappAutoPairingService.pairingsDidChangeNotification

  /// Deletes every stored pairing and forgets their display names.
  ///
  /// Same-account auto-pairing recreates complementary peers on the next
  /// reconcile. The pairing is gone here even if a peer never receives a
  /// close frame: the vault is the record this device honours.
  internal static func revokeEveryStoredPair() {
    let vault = RappDeviceVault()
    let pairIDs = (try? vault.activePairIDs()) ?? []
    for pairID in pairIDs {
      guard (try? RappPairRevocation.revoke(pairID: pairID, in: vault, clock: clock)) != nil
      else { continue }
      RappPairNames.forget(pairID: pairID)
    }
    try? vault.clearSelectedPair()
    RappPairNames.forgetAll()
    #if os(iOS)
      RemoteAccessServing.setEnabled(false)
    #endif
    #if os(macOS) || os(iOS)
      PersistentTokenRegistry.withdrawPublishedIdentity()
      #if REFINEID_STREAM_TRANSPORT
        PersistentTokenRegistry.shared.stopWatchingPresence()
      #endif
    #endif
    // Sweeping a thousand journals takes seconds; the list is already
    // empty in memory, so the wipe leaves the main thread.
    Task.detached(priority: .userInitiated) {
      _ = try? vault.deleteServiceNamespace(RappDeviceVault.serviceNamespace)
    }
    NotificationCenter.default.post(name: pairingsDidChangeNotification, object: nil)
  }

  /// Revokes every stored pairing whose peer left no name.
  ///
  /// A pairing is listed and chosen by the name its peer introduced
  /// itself with, so a record without one has nothing to be shown by.
  internal static func revokeNamelessPairs(in vault: RappDeviceVault) -> Int {
    let nameless = ((try? vault.activePairIDs()) ?? [])
      .filter { RappPairNames.name(forPairID: $0) == nil }
    var revoked = 0
    for pairID in nameless
    where (try? RappPairRevocation.revoke(pairID: pairID, in: vault, clock: clock)) != nil {
      revoked += 1
    }
    if let selected = try? vault.selectedPairID(), nameless.contains(selected) {
      try? vault.clearSelectedPair()
    }
    return revoked
  }

  /// Ends the session the pairing `pairID` carries, if one is open.
  private static func closeSessionForRevocation(pairID: Data) async {
    #if os(iOS) && REFINEID_LOCAL_CARD
      await PhonePersistentTokenRelay.shared.closeForRevocation(pairID: pairID)
    #endif
    #if (os(macOS) || os(iOS)) && REFINEID_STREAM_TRANSPORT
      await PersistentTokenRegistry.shared.closeSessionForRevocation(pairID: pairID)
    #endif
  }

  internal func refresh() {
    Task {
      do {
        pairs = try await catalog.activePairs()
        selectedPairID = try await catalog.selectedPair()?.pairID
      } catch {
        pairs = []
        selectedPairID = nil
      }
    }
  }

  internal func select(pairID: Data) {
    _ = try? vault.selectPair(pairID: pairID)
    selectedPairID = pairID
    refresh()
    NotificationCenter.default.post(name: Self.pairingsDidChangeNotification, object: nil)
  }

  /// Forgets one paired device through the vault the list is read from.
  ///
  /// A session open over the pairing closes with `pairing_revoked`
  /// first (RAPP v26.10.18 §4.6 item 1). The row goes with the record.
  /// The name goes only once the record is gone; a row that stays keeps
  /// its name.
  internal func revoke(pairID: Data) {
    Task { @MainActor in
      await Self.closeSessionForRevocation(pairID: pairID)
      revokeStored(pairID: pairID)
    }
  }

  private func revokeStored(pairID: Data) {
    guard (try? RappPairRevocation.revoke(pairID: pairID, in: vault, clock: clock)) != nil else {
      refresh()
      return
    }
    RappPairNames.forget(pairID: pairID)
    if selectedPairID == pairID {
      try? vault.clearSelectedPair()
    }
    refresh()
    #if os(macOS) || os(iOS)
      let remaining = (try? vault.activePairIDs()) ?? []
      if remaining.isEmpty || PersistentTokenRegistry.activePairID == pairID {
        PersistentTokenRegistry.withdrawPublishedIdentity()
      }
      #if REFINEID_STREAM_TRANSPORT
        PersistentTokenRegistry.shared.restartWatchingPresence()
      #endif
    #endif
    NotificationCenter.default.post(name: Self.pairingsDidChangeNotification, object: nil)
  }

  internal func revokeAll() {
    #if DEBUG
      // A revoked pretend pairing stays revoked.
      pretendPaired = false
    #endif
    // Revoking every pair disables serving too; see revokeEveryStoredPair.
    #if REFINEID_LOCAL_CARD && os(iOS)
      PhonePersistentTokenRelay.shared.stopServing()
    #endif
    Self.revokeEveryStoredPair()
    pairs = []
    selectedPairID = nil
    phase = .idle
    #if os(macOS) || os(iOS)
      PersistentTokenRegistry.withdrawPublishedIdentity()
      #if REFINEID_STREAM_TRANSPORT
        PersistentTokenRegistry.shared.stopWatchingPresence()
      #endif
    #endif
    RappAutoPairingService.shared.reconcile()
  }
}
