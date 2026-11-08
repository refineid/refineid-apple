// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import SwiftUI

/// The clock a revocation is stamped by.
private let clock = RappPlatformClock()

extension RappPairingModel {
  /// Posted when the set of active pairings changes.
  internal static let pairingsDidChangeNotification = Notification.Name(
    "fi.refineid.pairingsDidChange")

  /// Ends the session the pairing `pairID` carries with `pairing_revoked`;
  /// false when none is open or the close did not leave (RAPP v26.11.8
  /// §4.6 items 1 and 2).
  private static func closeSessionForRevocation(pairID: Data) async -> Bool {
    var closed = false
    #if os(iOS) && REFINEID_LOCAL_CARD
      closed = await PhonePersistentTokenRelay.shared.closeForRevocation(pairID: pairID) || closed
    #endif
    #if os(macOS) || os(iOS)
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
  /// (RAPP v26.11.8 §4.6).
  ///
  /// A session open over the pairing closes with `pairing_revoked` and,
  /// once that close left, the record and its key go at once. Otherwise the
  /// record is kept, forgotten, only to tell the peer on its next session.
  /// Either way the row goes, and the name with it once the record is no
  /// longer listed; a row that stays keeps its name.
  internal func forget(pairID: Data) async {
    let told = await Self.closeSessionForRevocation(pairID: pairID)
    forgetStored(pairID: pairID, told: told)
  }

  private func forgetStored(pairID: Data, told: Bool) {
    #if os(macOS) || os(iOS)
      let wasOffered = PersistentTokenRegistry.pairedPhoneID(in: vault) == pairID
    #endif
    let ended: Bool =
      if told {
        (try? RappPairRevocation.revoke(pairID: pairID, in: vault, clock: clock)) != nil
      } else {
        (try? catalogForget(pairID: pairID)) != nil
      }
    guard ended else {
      #if DEBUG
        DevErrorLog.report("pairing not forgotten: the vault refused", source: .app)
      #endif
      refresh()
      return
    }
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
      PersistentTokenRegistry.shared.restartWatchingPresence()
    #endif
    NotificationCenter.default.post(name: Self.pairingsDidChangeNotification, object: nil)
  }

  /// Marks the pairing forgotten: it serves nothing and keeps its key
  /// only for the `pairing_revoked` close on its next session.
  private func catalogForget(pairID: Data) throws {
    try RappPairRevocation.forget(
      try RappPairRecord.loadFromVault(pairId: pairID, vault: vault), in: vault, clock: clock)
  }

  /// Turns remote access off: this phone withdraws (RAPP v26.11.8 §4.5).
  ///
  /// Every open session closes with `service_withdrawn` before its
  /// transport goes, the stream listener announces the withdrawal, and the
  /// pairings stay, so turning remote access on again serves the paired
  /// computers at once. An attempt to pair ends.
  internal func stopRemoteAccess() {
    resetAttempt()
    #if os(iOS)
      RemoteAccessServing.setEnabled(false)
    #endif
  }
}
