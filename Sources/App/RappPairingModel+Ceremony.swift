// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import SwiftUI

/// What the model does with each event the pairing ceremony reports.
extension RappPairingModel {
  internal func receive(
    _ event: RappPairingCoordinator.Event,
    from coordinator: RappPairingCoordinator
  ) {
    guard self.coordinator === coordinator else { return }
    switch event {
    case .offerRestored:
      restoreCustodianOffer(coordinator: coordinator)

    case .peerIntroduced(let peer):
      let name = peer.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else {
        ceremonyEnded(String(localized: "The device did not give its name"))
        return
      }
      reviewedPeerName = name

    case .paired(let pair):
      handlePaired(pair)

    case .closed(let reason):
      guard !isFinished else { return }
      handleClosed(reason)
    }
  }

  private func handleClosed(_ reason: RappPairingCoordinator.CloseReason) {
    switch (reason, phase) {
    case (.offerExpired, .offer):
      // An unused code lapses with its offer after five minutes; the next one follows.
      createOffer()

    case (.attemptsExhausted, _):
      // The next offer shows the lockout and the code once it lifts.
      RappPairingBackoff.shared.recordLockout()
      ceremonyEnded(String(localized: "Pairing locked after three incorrect codes."))

    case (_, .offer):
      ceremonyEnded(String(localized: "Pairing ended before it was completed"))

    default:
      ceremonyEnded(String(localized: "The pairing code was not accepted"))
    }
  }

  /// Keeps the pair under the name its peer gave.
  ///
  /// A pair whose peer gave none is revoked before it can be listed or
  /// chosen. A phone that offered lists the new computer and shows the
  /// next code.
  private func handlePaired(_ pair: RappPairingCoordinator.PairSummary) {
    guard let reviewedPeerName else {
      try? RappPairRevocation.revoke(pairID: pair.pairID, in: vault, clock: RappPlatformClock())
      if (try? vault.selectedPairID()) == pair.pairID {
        try? vault.clearSelectedPair()
      }
      ceremonyEnded(String(localized: "The device did not give its name"))
      return
    }
    do {
      try vault.selectPair(pairID: pair.pairID)
      RappPairNames.remember(reviewedPeerName, pairID: pair.pairID)
      supersedeOlderPairings(with: pair.pairID)
      RappPairingBackoff.shared.recordSuccess()
      selectedPairID = pair.pairID
      refresh()
      serveNewPairing()
      #if os(iOS)
        if isOffering {
          createOffer()
          return
        }
      #endif
      phase = .paired(pair)
      finishAttempt()
      #if os(macOS)
        PersistentTokenRegistry.shared.startAfterPairing()
      #endif
    } catch {
      ceremonyEnded(String(localized: "The paired device could not be selected"))
    }
  }

  /// Keeps showing the same code after a failed attempt, listening afresh.
  private func restoreCustodianOffer(coordinator: RappPairingCoordinator) {
    relay?.cancel()
    let replacement = makeRelay(role: .cardHolder)
    let replacementTransport = makeTransport(relay: replacement)
    relay = replacement
    Task { @MainActor [weak self] in
      guard await coordinator.replaceTransport(replacementTransport),
        let self,
        self.coordinator === coordinator,
        !isFinished
      else {
        self?.fail(String(localized: "Pairing could not be started"))
        return
      }
      replacement.start()
    }
  }

  /// Revokes the pairings the new one replaces.
  ///
  /// Pairing the same two devices again makes a fresh record and leaves the
  /// last one behind, so a device that has been paired a few times holds
  /// several records naming one peer and only one of them answers. The
  /// newest is the one both sides just agreed on; the rest are spent.
  ///
  /// Only pairings naming the same peer are taken. A device legitimately
  /// pairs with more than one other, and those records are not this one's
  /// to revoke.
  internal func supersedeOlderPairings(with keptPairID: Data) {
    guard let keptName = RappPairNames.name(forPairID: keptPairID) else { return }
    let superseded = ((try? vault.activePairIDs()) ?? [])
      .filter { pairID in
        pairID != keptPairID && RappPairNames.name(forPairID: pairID) == keptName
      }
    let clock = RappPlatformClock()
    for pairID in superseded {
      try? RappPairRevocation.revoke(pairID: pairID, in: vault, clock: clock)
      RappPairNames.forget(pairID: pairID)
    }
  }
}
