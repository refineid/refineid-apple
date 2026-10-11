// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import SwiftUI

/// Milliseconds in one second, for the stamp a revocation carries.
private let millisecondsPerSecond: TimeInterval = 1_000

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
    let now = UInt64(Date().timeIntervalSince1970 * millisecondsPerSecond)
    for pairID in pairIDs {
      guard (try? vault.revokePair(pairID: pairID, revokedAtMilliseconds: now)) != nil
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

  /// Forgets one paired computer through the vault the list is read from,
  /// so the row goes with the record. The name goes only once the record
  /// is gone; a row that stays keeps its name.
  internal func revoke(pairID: Data) {
    let now = UInt64(Date().timeIntervalSince1970 * millisecondsPerSecond)
    guard (try? vault.revokePair(pairID: pairID, revokedAtMilliseconds: now)) != nil else {
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
      PhonePersistentTokenRelay.shared.stopListening()
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
