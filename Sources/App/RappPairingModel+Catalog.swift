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
  /// close frame: the vault is the record this device honours, and the
  /// namespace it lives in is wiped.
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
    // Sweeping the keychain namespace takes time; the list is already
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

  /// Ends the session the pairing `pairID` carries with `pairing_revoked`;
  /// false when none is open (RAPP v26.10.21 §4.6 item 1).
  private static func closeSessionForRevocation(pairID: Data) async -> Bool {
    var closed = false
    #if os(iOS) && REFINEID_LOCAL_CARD
      closed = await PhonePersistentTokenRelay.shared.closeForRevocation(pairID: pairID) || closed
    #endif
    #if (os(macOS) || os(iOS)) && REFINEID_STREAM_TRANSPORT
      closed =
        await PersistentTokenRegistry.shared.closeSessionForRevocation(pairID: pairID) || closed
    #endif
    return closed
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

  /// Forgets one paired device through the vault the list is read from
  /// (RAPP v26.10.21 §4.6).
  ///
  /// A session open over the pairing closes with `pairing_revoked` and the
  /// record goes at once. Without one the record is kept, forgotten, only
  /// to tell the peer on its next session. Either way the row goes, and
  /// the name with it once the record is no longer listed; a row that
  /// stays keeps its name.
  internal func revoke(pairID: Data) {
    Task { @MainActor in
      let told = await Self.closeSessionForRevocation(pairID: pairID)
      forgetStored(pairID: pairID, told: told)
    }
  }

  private func forgetStored(pairID: Data, told: Bool) {
    #if os(macOS) || os(iOS)
      let wasOffered = PersistentTokenRegistry.activePairID == pairID
    #endif
    let ended: Bool =
      if told {
        (try? RappPairRevocation.revoke(pairID: pairID, in: vault, clock: clock)) != nil
      } else {
        (try? catalogForget(pairID: pairID)) != nil
      }
    guard ended else {
      refresh()
      return
    }
    RappPairNames.forget(pairID: pairID)
    if selectedPairID == pairID {
      try? vault.clearSelectedPair()
    }
    refresh()
    #if os(macOS) || os(iOS)
      let usable = ((try? vault.activePairIDs()) ?? []).contains { remaining in
        (try? RappPairRecord.loadFromVault(pairId: remaining, vault: vault))?.metadata()
          .forgottenAtMs == nil
      }
      if !usable || wasOffered {
        PersistentTokenRegistry.withdrawPublishedIdentity()
      }
      #if REFINEID_STREAM_TRANSPORT
        PersistentTokenRegistry.shared.restartWatchingPresence()
      #endif
    #endif
    NotificationCenter.default.post(name: Self.pairingsDidChangeNotification, object: nil)
  }

  /// Marks the pairing forgotten: it serves nothing and keeps its key
  /// only for the `pairing_revoked` close on its next session.
  private func catalogForget(pairID: Data) throws {
    try RappPairRevocation.forget(
      try RappPairRecord.loadFromVault(pairId: pairID, vault: vault), in: vault, clock: clock)
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
