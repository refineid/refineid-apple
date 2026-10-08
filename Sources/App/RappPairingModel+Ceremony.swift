// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import SwiftUI

/// Milliseconds in one second, for the stamp a revocation carries.
private let millisecondsPerSecond: TimeInterval = 1_000

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
      reviewedPeerName = peer.displayName

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
      // An unused code lapses after a minute; the custodian shows a new one.
      createOffer()

    case (.attemptsExhausted, _):
      RappPairingBackoff.shared.recordLockout()
      fail(String(localized: "Pairing locked after three incorrect codes."))

    case (_, .offer):
      fail(String(localized: "Pairing ended before it was completed"))

    default:
      fail(String(localized: "The pairing code was not accepted"))
    }
  }

  private func handlePaired(_ pair: RappPairingCoordinator.PairSummary) {
    do {
      try vault.selectPair(pairID: pair.pairID)
      if let reviewedPeerName {
        RappPairNames.remember(reviewedPeerName, pairID: pair.pairID)
      }
      supersedeOlderPairings(with: pair.pairID)
      RappPairingBackoff.shared.recordSuccess()
      selectedPairID = pair.pairID
      phase = .paired(pair)
      refresh()
      finishAttempt()
      resumeRegularRelay()
      #if os(macOS)
        PersistentTokenRegistry.shared.startAfterPairing()
      #endif
    } catch {
      fail(String(localized: "The paired device could not be selected"))
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
    let keptName = RappPairNames.name(forPairID: keptPairID)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let superseded = ((try? vault.activePairIDs()) ?? [])
      .filter { pairID in
        guard pairID != keptPairID else { return false }
        let olderName = RappPairNames.name(forPairID: pairID)?
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if let keptName, !keptName.isEmpty, let olderName, !olderName.isEmpty {
          return olderName == keptName
        }
        let keptBlank = keptName == nil || keptName?.isEmpty == true
        let olderBlank = olderName == nil || olderName?.isEmpty == true
        if keptBlank, olderBlank {
          return true
        }
        return false
      }
    let now = UInt64(Date().timeIntervalSince1970 * millisecondsPerSecond)
    for pairID in superseded {
      try? vault.revokePair(pairID: pairID, revokedAtMilliseconds: now)
      RappPairNames.forget(pairID: pairID)
    }
  }
}
