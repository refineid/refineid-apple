// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import Security
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
    case .ceremonyEnded(.outOfSpace):
      .reported(DiskFullMessage.text)

    case .ceremonyEnded(.persistenceFailure(let status)):
      .reported(notStoredMessage(status: status))

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

  /// What the holder is told when the keychain did not store a pairing,
  /// with the cause the system gives (RAPP v26.11.2 §4.3 item 4).
  nonisolated internal static func notStoredMessage(status: OSStatus?) -> String {
    guard let status, let cause = SecCopyErrorMessageString(status, nil) as String? else {
      return String(localized: "The pairing could not be stored.")
    }
    return String(localized: "The pairing could not be stored. \(cause)")
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

    case .keyConfirmed, .peerIntroduced:
      // The peer's name arrives in the stored pair.
      break

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

    case .peerIntroduced:
      // The peer's name arrives in the stored pair.
      break

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

  private func handleClosed(_ reason: RappPairingCoordinator.CloseReason) {
    switch reason {
    case .offerExpired:
      // An unused code lapses with its offer after five minutes; the next one follows.
      createOffer()

    case .outOfSpace:
      // A next offer could not be stored either.
      fail(.reported(DiskFullMessage.text))

    case .persistenceFailure(let status):
      // A next offer could not be stored either.
      #if DEBUG
        DevErrorLog.report(
          "pairing not stored: keychain status \(status.map(String.init) ?? "none")",
          source: .app)
      #endif
      fail(.reported(Self.notStoredMessage(status: status)))

    case .attemptTimedOut, .custodianBusy, .localRequest,
      .protocolFailure, .storageUnconfirmed, .transportFailure:
      ceremonyEnded(String(localized: "Pairing ended before it was completed."))
    }
  }

  /// Selects the new pair.
  ///
  /// The pair carries the name its peer gave (RAPP v26.11.2 §4.3 item 3).
  /// A phone that offered lists the new computer and shows the next code.
  private func handlePaired(_ pair: RappPairingCoordinator.PairSummary) {
    do {
      try vault.selectPair(pairID: pair.pairID)
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
      if pair.role == .requester {
        PersistentTokenRegistry.shared.forgetReplacedPairings(
          keeping: pair.pairID, in: vault)
      }
      #if os(macOS)
        PersistentTokenRegistry.shared.startAfterPairing()
      #endif
    } catch  where StorageFailure.isOutOfSpace(error) {
      fail(.reported(DiskFullMessage.text))
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
}
