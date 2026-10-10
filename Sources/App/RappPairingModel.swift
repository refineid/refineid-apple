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
    case failed(String)
  }

  /// The in-protocol name this device introduces itself with.
  internal static var localDisplayName: String {
    #if os(macOS)
      Host.current().localizedName ?? String(localized: "Mac")
    #else
      UIDevice.current.name
    #endif
  }

  /// The in-protocol platform name this device introduces itself with.
  internal static var localPlatform: String {
    #if os(macOS)
      "macOS"
    #else
      "iOS"
    #endif
  }

  /// The transport profile a ceremony runs over in this build.
  ///
  /// The custodian's offer names it (RAPP v26.10.9 §2.2); the requester
  /// finds the holder by its published pairing attributes and reads the
  /// offer it serves.
  internal static var ceremonyTransportProfile: String {
    #if REFINEID_STREAM_TRANSPORT
      rappStreamProfileName()
    #else
      RappApplePeerProfile.name
    #endif
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

  internal let vault: RappDeviceVault
  internal let catalog: RappPairCatalog
  internal var relay: PairingRelay?
  internal var relayGeneration: UUID?
  internal var coordinator: RappPairingCoordinator?
  internal var eventTask: Task<Void, Never>?
  internal var pairingTimeoutTask: Task<Void, Never>?
  internal var reviewedPeerName: String?

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

  internal func createOffer(customCode: String?) {
    resetAttempt()
    #if os(iOS)
      RemoteAccessServing.setEnabled(true)
    #endif
    #if REFINEID_LOCAL_CARD && os(iOS)
      PhonePersistentTokenRelay.shared.suspendForPairing()
    #endif
    let wait = RappPairingBackoff.shared.secondsUntilNextOffer()
    guard wait == 0 else {
      phase = .failed(String(localized: "Pairing locked. Try again in \(wait) s."))
      scheduleOfferAfterLockout(seconds: wait)
      return
    }
    let code = customCode.map(RappPairingCode.normalize) ?? RappPairingCode.generate()
    let custodianRelay = makeRelay(role: .cardHolder)
    do {
      let newCoordinator = try RappPairingCoordinator.custodian(
        options: options(code: code, transport: makeTransport(relay: custodianRelay)))
      pairingCode = code
      install(coordinator: newCoordinator, relay: custodianRelay)
      phase = .offer(code)
      Task { await newCoordinator.start() }
      custodianRelay.start()
    } catch {
      fail(String(localized: "Pairing could not be started"))
    }
  }

  /// The ceremony options both roles share; the offer hash binds them.
  internal func options(
    code: String, transport: any RappFrameTransport
  ) -> RappPairingCoordinator.Options {
    RappPairingCoordinator.Options(
      code: code,
      profiles: RappApplePeerProfile.supportedCredentialProfiles,
      transportProfile: Self.ceremonyTransportProfile,
      displayName: Self.localDisplayName,
      platform: Self.localPlatform,
      vault: vault,
      transport: transport)
  }

  private func scheduleOfferAfterLockout(seconds: UInt64) {
    pairingTimeoutTask?.cancel()
    pairingTimeoutTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .seconds(seconds))
      } catch {
        return
      }
      guard let self, case .failed = phase else { return }
      createOffer()
    }
  }

  internal func cancel() {
    let activeCoordinator = coordinator
    relay?.cancel()
    finishAttempt()
    phase = .idle
    Task { await activeCoordinator?.close() }
    resumeRegularRelay()
  }

  internal func makeRelay(role: PersistentRelayRole) -> PairingRelay {
    let generation = UUID()
    relayGeneration = generation
    let displayName: String
    switch role {
    case .host:
      #if os(macOS)
        displayName = String(localized: "RefineID Mac")
      #else
        displayName = String(localized: "RefineID iPad")
      #endif

    case .cardHolder:
      displayName = String(localized: "RefineID iPhone")
    }
    return PairingRelay(
      role: role,
      displayName: displayName
    ) { [weak self] event in
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
    guard let coordinator else { return }
    switch event {
    case .connected:
      deliverInOrder { await coordinator.transportConnected() }

    case .frame(let frame):
      deliverInOrder { await coordinator.receive(frame) }

    case .closed:
      guard !isFinished else {
        finishAttempt()
        return
      }
      deliverInOrder { await coordinator.transportClosed() }
    }
  }

  /// Runs `work` after every delivery enqueued before it; a peer that
  /// outruns the bounded chain ends the attempt.
  private func deliverInOrder(_ work: @escaping @Sendable () async -> Void) {
    if eventDelivery.deliver(work) { return }
    relay?.cancel()
  }

  internal func fail(_ message: String) {
    let activeCoordinator = coordinator
    phase = .failed(message)
    relay?.cancel()
    finishAttempt()
    Task { await activeCoordinator?.close() }
    resumeRegularRelay()
  }

  internal func finishAttempt() {
    relay = nil
    relayGeneration = nil
    coordinator = nil
    eventTask?.cancel()
    eventTask = nil
    pairingTimeoutTask?.cancel()
    pairingTimeoutTask = nil
    eventDelivery.reset()
  }

  internal func resetAttempt() {
    let activeCoordinator = coordinator
    relay?.cancel()
    finishAttempt()
    phase = .idle
    Task { await activeCoordinator?.close() }
  }

  internal func resumeRegularRelay() {
    #if REFINEID_LOCAL_CARD && os(iOS)
      PhonePersistentTokenRelay.shared.resumeAfterUserAction()
    #endif
  }
}
