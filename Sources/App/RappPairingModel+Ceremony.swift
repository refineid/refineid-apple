// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import SwiftUI

/// What the model does with each event the pairing ceremony reports.
extension RappPairingModel {
  /// What the requester tells its user when the search ends without a
  /// pairing; nothing when it was closed here.
  ///
  /// No message names a custodian (STPA CC-84), and the code is called not
  /// accepted only when every custodian tried refused it (CC-83).
  nonisolated internal static func failure(
    for reason: RappPairingSearch<PairingEndpoint>.CloseReason
  ) -> Failure? {
    switch reason {
    case .ceremonyEnded:
      .reported(String(localized: "Pairing ended before it was completed."))

    case .interrupted, .localRequest:
      nil

    case .localNetworkDenied:
      .localNetworkDenied

    case .noneInPairingMode:
      .reported(String(localized: "No phone in pairing mode was found."))

    case .notAccepted:
      .reported(String(localized: "The pairing code was not accepted."))

    case .unreachable:
      .unreachable
    }
  }

  /// What the custodian's ceremony reports.
  internal func receive(
    _ event: RappPairingCoordinator.Event,
    from coordinator: RappPairingCoordinator
  ) {
    guard self.coordinator === coordinator else { return }
    switch event {
    case .offerRestored:
      restoreCustodianOffer(coordinator: coordinator)

    case .keyConfirmed:
      break

    case .peerIntroduced(let peer):
      introduce(peer)

    case .paired(let pair):
      handlePaired(pair)

    case .closed(let reason):
      guard !isFinished else { return }
      handleClosed(reason)
    }
  }

  /// What the requester's search reports.
  internal func receive(
    _ event: RappPairingSearch<PairingEndpoint>.Event,
    from search: RappPairingSearch<PairingEndpoint>
  ) {
    guard self.search === search else { return }
    switch event {
    case .declined(let refusal):
      #if DEBUG
        DevErrorLog.report(
          "pairing: a phone in pairing mode did not take the code: "
            + DevErrorLog.caseName(of: refusal),
          source: .app)
      #endif

    case .peerIntroduced(let peer):
      introduce(peer)

    case .paired(let pair):
      handlePaired(pair)

    case .closed(.interrupted):
      // The code entry is offered afresh once remote use resumes.
      resetAttempt()

    case .closed(let reason):
      guard !isFinished, let failure = Self.failure(for: reason) else { return }
      #if DEBUG
        DevErrorLog.report(
          "pairing ended: " + DevErrorLog.caseName(of: reason), source: .app)
      #endif
      fail(failure)
      if failure == .localNetworkDenied {
        PersistentTokenRegistry.shared.localNetworkDenied = true
      }
    }
  }

  /// Keeps the name and the platform the peer introduced itself with,
  /// inside the authenticated pairing channel.
  private func introduce(_ peer: RappPairingCoordinator.Peer) {
    let name = peer.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      ceremonyEnded(String(localized: "The device did not give its name."))
      return
    }
    reviewedPeerName = name
  }

  private func handleClosed(_ reason: RappPairingCoordinator.CloseReason) {
    switch reason {
    case .offerExpired:
      // An unused code lapses with its offer after five minutes; the next one follows.
      createOffer()

    case .attemptTimedOut, .custodianBusy, .localRequest, .persistenceFailure,
      .protocolFailure, .storageUnconfirmed, .transportFailure:
      ceremonyEnded(String(localized: "Pairing ended before it was completed."))
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
      ceremonyEnded(String(localized: "The device did not give its name."))
      return
    }
    do {
      try vault.selectPair(pairID: pair.pairID)
      RappPairNames.remember(reviewedPeerName, pairID: pair.pairID)
      supersedeOlderPairings(with: pair.pairID)
      selectedPairID = pair.pairID
      refresh()
      serveNewPairing()
      Task { await RemoteAccessPermissions.requestNotificationsIfUndecided() }
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
      ceremonyEnded(String(localized: "The paired device could not be selected."))
    }
  }

  /// Keeps showing the same code after a failed attempt, listening afresh.
  private func restoreCustodianOffer(coordinator: RappPairingCoordinator) {
    relay?.cancel()
    let replacement = makeRelay()
    replacement.busyAnswer = { coordinator.busyAnswer() }
    let replacementTransport = makeTransport(relay: replacement)
    relay = replacement
    Task { @MainActor [weak self] in
      guard await coordinator.replaceTransport(replacementTransport),
        let self,
        self.coordinator === coordinator,
        !isFinished
      else {
        self?.fail(.reported(String(localized: "Pairing could not be started.")))
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
