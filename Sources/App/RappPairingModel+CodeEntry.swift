// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import SwiftUI

/// The requester's half of the ceremony: typing the code the custodian
/// shows and pairing with it.
extension RappPairingModel {
  /// How long the requester looks for a custodian before giving up.
  private static let pairingTimeoutNanoseconds: UInt64 = 15_000_000_000

  internal func startCodeEntry() {
    resetAttempt()
    phase = .codeEntry
  }

  internal func acceptPairingCode(_ rawCode: String) {
    resetAttempt()
    let code = RappPairingCode.normalize(rawCode)
    guard RappPairingCode.isValid(code) else {
      fail(String(localized: "The pairing code is invalid"))
      return
    }
    let requesterRelay = makeRelay(role: .host)
    do {
      let newCoordinator = try RappPairingCoordinator.requester(
        options: options(code: code, transport: makeTransport(relay: requesterRelay)))
      install(coordinator: newCoordinator, relay: requesterRelay)
      phase = .connecting
      Task { await newCoordinator.start() }
      requesterRelay.start()
      schedulePairingTimeout()
    } catch {
      fail(String(localized: "The pairing code is invalid"))
    }
  }

  private func schedulePairingTimeout() {
    pairingTimeoutTask?.cancel()
    pairingTimeoutTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: Self.pairingTimeoutNanoseconds)
        guard let self, !isFinished, phase == .connecting else { return }
        fail(String(localized: "Could not find a device offering this pairing code."))
      } catch {
        // A cancelled timeout attempt needs no recovery.
      }
    }
  }
}
