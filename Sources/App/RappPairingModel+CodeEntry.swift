// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import SwiftUI

/// The requester's half of the ceremony: typing the code the custodian
/// shows and pairing with it.
extension RappPairingModel {
  /// How long the requester looks for custodians in pairing mode.
  private static let discoveryNanoseconds: UInt64 = 15_000_000_000

  /// Ends the code being tried as remote use stops being available.
  ///
  /// Remote use was turned off, or a card in this device's reader suspends
  /// it (the state model's `search_interrupted`). The connection open for
  /// the code closes and nothing is reported.
  internal func interruptSearch() {
    let activeSearch = search
    relay?.cancel()
    finishAttempt()
    phase = .idle
    Task { await activeSearch?.interrupt() }
  }

  internal func startCodeEntry() {
    resetAttempt()
    phase = .codeEntry
  }

  /// Tries the typed code on every custodian found in pairing mode, one at
  /// a time, until one takes it (RAPP v26.10.22 §4.2, "Trying Each
  /// Custodian in Pairing Mode").
  internal func acceptPairingCode(_ rawCode: String) {
    resetAttempt()
    let code = RappPairingCode.normalize(rawCode)
    guard RappPairingCode.isValid(code) else {
      fail(.reported(String(localized: "The pairing code is invalid")))
      return
    }
    let newSearch: RappPairingSearch<PairingEndpoint>
    do {
      newSearch = try RappPairingSearch(
        options: options(code: code),
        remoteUseAvailable: { RemoteUseAvailability.isAvailable },
        dial: { endpoint in PairingCandidateLink.dial(endpoint) })
    } catch {
      fail(.reported(String(localized: "The pairing code is invalid")))
      return
    }
    install(search: newSearch)
    phase = .connecting
    discover(for: newSearch)
  }

  /// Hands every custodian found in pairing mode to `search`, in the order
  /// found, until the requester stops looking.
  private func discover(for search: RappPairingSearch<PairingEndpoint>) {
    let discovery = PairingCandidateLink.discover()
    stopDiscovery = discovery.stop
    Task {
      for await endpoint in discovery.found {
        await search.found(endpoint)
      }
      await search.endDiscovery()
    }
    pairingTimeoutTask?.cancel()
    pairingTimeoutTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: Self.discoveryNanoseconds)
      } catch {
        return
      }
      guard let self, self.search === search else { return }
      stopDiscovery?()
      stopDiscovery = nil
    }
  }

  private func install(search: RappPairingSearch<PairingEndpoint>) {
    self.search = search
    eventTask = Task { [weak self] in
      for await event in search.events {
        self?.receive(event, from: search)
      }
    }
  }
}
