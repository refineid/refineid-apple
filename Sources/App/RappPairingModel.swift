// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import SwiftUI

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

@MainActor
internal final class RappPairingModel: ObservableObject {
  internal enum Phase: Equatable {
    case idle
    case offer(String)
    case codeEntry
    case connecting
    case paired(RappPairingCoordinator.PairSummary)
    case failed(Failure)
  }

  /// Why an attempt ended without a pairing.
  internal enum Failure: Equatable {
    /// The platform keeps this app off the local network; the holder
    /// allows it in the settings.
    case localNetworkDenied
    /// A phone was found and could not be reached; the holder checks the
    /// network and the permission.
    case unreachable
    /// Anything else, in the words the user is told.
    case reported(String)

    /// What the user is told now.
    internal var message: String {
      switch self {
      case .localNetworkDenied:
        LocalNetworkSettings.deniedMessage

      case .unreachable:
        LocalNetworkSettings.unreachableMessage

      case .reported(let message):
        message
      }
    }

    /// Whether the failure is shown with the way to the local-network
    /// settings.
    internal var opensNetworkSettings: Bool {
      switch self {
      case .localNetworkDenied, .unreachable:
        true

      case .reported:
        false
      }
    }
  }

  @Published internal var phase = Phase.idle
  @Published internal var pairs: [RappPairingCoordinator.PairSummary] = []
  /// A `--pretend-paired` launch starts the row paired; revoking clears it.
  ///
  /// The vault stays empty: nothing here is cryptographic, it only drives
  /// the pairing row through its states for the UI suites.
  @Published internal var pretendPaired = false
  @Published internal var selectedPairID: Data?
  @Published internal var pairingCode: String?
  /// Whether the ceremony under way is this device's own offer: a phone
  /// shows a code for as long as remote access is on, so an offer that
  /// ends, however it ends, is followed by the next one.
  internal private(set) var isOffering = false

  internal let vault: RappDeviceVault
  internal let catalog: RappPairCatalog
  internal var relay: PairingRelay?
  internal var relayGeneration: UUID?
  /// Which connection this device's offer serves, across its transports.
  internal var claim: PairingConnectionClaim?
  internal var coordinator: RappPairingCoordinator?
  /// The requester's tries of the code its user typed.
  internal var search: RappPairingSearch<PairingEndpoint>?
  /// The route of the requester's last pairing connection.
  internal var lastDialed: LastDialedEndpoint?
  /// Stops looking for custodians in pairing mode.
  internal var stopDiscovery: (@Sendable () -> Void)?
  internal var eventTask: Task<Void, Never>?
  internal var pairingTimeoutTask: Task<Void, Never>?

  /// Ceremony events enter the coordinator in arrival order through
  /// this bounded chain; reset between attempts.
  private let eventDelivery = OrderedDelivery(
    capacity: OrderedDelivery.relayFrameCapacity)

  internal var isFinished: Bool {
    switch phase {
    case .paired, .failed:
      true

    case .idle, .offer, .codeEntry, .connecting:
      false
    }
  }

  internal var hasActivePairs: Bool {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--mock-remote-connected") {
        return true
      }
      if pretendPaired {
        return true
      }
    #endif
    return !pairs.isEmpty
  }

  internal init() {
    let newVault = RappDeviceVault()
    self.vault = newVault
    self.catalog = RappPairCatalog(vault: newVault)
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--pretend-paired") {
        pretendPaired = true
      }
    #endif
  }

  internal init(vault: RappDeviceVault) {
    self.vault = vault
    self.catalog = RappPairCatalog(vault: vault)
  }

  /// Shows a fresh code and waits for a requester to type it: the
  /// custodian's half of the ceremony.
  internal func createOffer() {
    createOffer(customCode: nil)
  }

  /// Shows a pairing code and serves it; only a phone does (RAPP v26.11.8
  /// §1): an iPad or a Mac is a requester and offers nothing.
  internal func createOffer(customCode: String?) {
    guard SupportedCardTransports.servesRemoteCards else { return }
    resetAttempt()
    isOffering = true
    #if os(iOS)
      RemoteAccessServing.setEnabled(true)
    #endif
    let code = customCode.map(RappPairingCode.normalize) ?? RappPairingCode.generate()
    let custodianRelay = makeRelay()
    do {
      let newCoordinator = try RappPairingCoordinator.custodian(options: options(code: code))
      pairingCode = code
      custodianRelay.busyAnswer = { newCoordinator.busyAnswer() }
      install(coordinator: newCoordinator, relay: custodianRelay)
      let offerClaim = PairingConnectionClaim()
      claim = offerClaim
      phase = .offer(code)
      Task { await newCoordinator.start() }
      custodianRelay.start()
      #if os(iOS) && REFINEID_LOCAL_CARD
        offerOverBluetooth(newCoordinator, claim: offerClaim)
      #endif
    } catch {
      fail(
        .reported(
          DiskFullMessage.message(
            for: error, otherwise: String(localized: "Pairing could not be started."))))
    }
  }

  /// The ceremony options both roles share; the offer hash binds them.
  ///
  /// A phone's offer lists the stream and Bluetooth, and a requester pairs
  /// over either (RAPP v26.11.8 §4.2).
  internal func options(code: String) -> RappPairingCoordinator.Options {
    RappPairingCoordinator.Options(
      code: code,
      profiles: rappCredentialProfiles(),
      transportProfiles: [RappBleGattProfile.name, rappStreamProfileName()],
      displayName: RappLocalName.displayName,
      platform: RappLocalName.platform,
      vault: vault)
  }

  internal func cancel() {
    resetAttempt()
  }

  /// Ends the ceremony the way its role calls for: a phone's own offer
  /// is followed by the next one; a requester reports `failure`.
  internal func ceremonyEnded(_ failure: String) {
    #if os(iOS)
      if isOffering {
        createOffer()
        return
      }
    #endif
    fail(.reported(failure))
  }

  /// The channel this device's offer is served on.
  internal func makeRelay() -> PairingRelay {
    let generation = UUID()
    relayGeneration = generation
    return PairingRelay { [weak self] event in
      Task { @MainActor in self?.receive(event, generation: generation) }
    }
  }

  internal func install(
    coordinator: RappPairingCoordinator,
    relay: PairingRelay
  ) {
    self.coordinator = coordinator
    self.relay = relay
    eventTask = Task { [weak self] in
      for await event in coordinator.events {
        self?.receive(event, from: coordinator)
      }
    }
  }

  private func receive(
    _ event: PersistentRelayEvent,
    generation: UUID
  ) {
    guard generation == relayGeneration else { return }
    guard let coordinator, let claim, let relay else { return }
    switch event {
    case .connected:
      guard claim.claim(.stream) else {
        refuseStreamConnection(relay: relay, coordinator: coordinator)
        return
      }
      let transport = makeTransport(relay: relay)
      deliverInOrder { [weak self] in
        guard await coordinator.attach(transport, transportProfile: rappStreamProfileName())
        else {
          claim.release(.stream)
          await self?.refuseStreamConnection(relay: relay, coordinator: coordinator)
          return
        }
        await coordinator.transportConnected()
      }

    case .frame(let frame):
      guard claim.holds(.stream) else { return }
      deliverInOrder { await coordinator.receive(frame) }

    case .closed:
      guard !isFinished else {
        finishAttempt()
        return
      }
      guard claim.holds(.stream) else { return }
      deliverInOrder {
        await coordinator.transportClosed()
        claim.release(.stream)
      }
    }
  }

  /// Runs `work` after every delivery enqueued before it; a peer that
  /// outruns the bounded chain ends the ceremony, on whichever transport it
  /// runs, and a phone shows its next offer.
  internal func deliverInOrder(_ work: @escaping @Sendable () async -> Void) {
    if eventDelivery.deliver(work) { return }
    #if DEBUG
      DevErrorLog.report("pairing: frames outran the delivery queue", source: .app)
    #endif
    ceremonyEnded(String(localized: "Pairing ended before it was completed."))
  }

  internal func fail(_ failure: Failure) {
    let activeCoordinator = coordinator
    let activeSearch = search
    phase = .failed(failure)
    relay?.cancel()
    finishAttempt()
    Task {
      await activeCoordinator?.close()
      await activeSearch?.close()
    }
  }

  internal func finishAttempt() {
    isOffering = false
    relay = nil
    relayGeneration = nil
    if claim != nil {
      claim = nil
      #if os(iOS) && REFINEID_LOCAL_CARD
        PhonePersistentTokenRelay.shared.withdrawPairingOverBluetooth()
      #endif
    }
    coordinator = nil
    search = nil
    stopDiscovery?()
    stopDiscovery = nil
    eventTask?.cancel()
    eventTask = nil
    pairingTimeoutTask?.cancel()
    pairingTimeoutTask = nil
    eventDelivery.reset()
  }

  internal func resetAttempt() {
    let activeCoordinator = coordinator
    let activeSearch = search
    relay?.cancel()
    finishAttempt()
    phase = .idle
    Task {
      await activeCoordinator?.close()
      await activeSearch?.close()
    }
  }

  /// Serves the paired computers, the one just paired among them: a
  /// relay not yet listening starts, and one already listening announces
  /// the new pairing in its session record at once.
  internal func serveNewPairing() {
    #if REFINEID_LOCAL_CARD && os(iOS)
      PhonePersistentTokenRelay.shared.start()
      PhonePersistentTokenRelay.shared.refreshSessionRecord()
    #endif
  }
}
