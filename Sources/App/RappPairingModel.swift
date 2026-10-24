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
    /// Too many incorrect codes; a new offer is shown at `until`.
    case locked(until: Date)
    /// Anything else, in the words the user is told.
    case reported(String)

    /// What the user is told now; a shown lockout redraws its own
    /// countdown (``PairingLockCountdown``).
    internal var message: String {
      switch self {
      case .localNetworkDenied:
        LocalNetworkSettings.deniedMessage

      case .unreachable:
        LocalNetworkSettings.unreachableMessage

      case .locked(let until):
        PairingLockCountdown.message(until: until, at: Date())

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

      case .locked, .reported:
        false
      }
    }
  }

  /// The in-protocol name this device introduces itself with.
  internal static var localDisplayName: String {
    #if os(macOS)
      Host.current().localizedName ?? String(localized: "Mac")
    #else
      UIDevice.current.name
    #endif
  }

  /// The platform description this device introduces itself with: the
  /// device's model, which tells a person which device this is.
  internal static var localPlatform: String {
    DeviceModel.description
  }

  /// The transport profile a ceremony runs over in this build.
  ///
  /// The custodian's offer names it (RAPP v26.10.22 §2.2); the requester
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
  /// Whether the ceremony under way is this device's own offer: a phone
  /// shows a code for as long as remote access is on, so an offer that
  /// ends, however it ends, is followed by the next one.
  internal private(set) var isOffering = false

  internal let vault: RappDeviceVault
  internal let catalog: RappPairCatalog
  internal var relay: PairingRelay?
  internal var relayGeneration: UUID?
  internal var coordinator: RappPairingCoordinator?
  /// The requester's tries of the code its user typed.
  internal var search: RappPairingSearch<PairingEndpoint>?
  /// Stops looking for custodians in pairing mode.
  internal var stopDiscovery: (@Sendable () -> Void)?
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
    isOffering = true
    #if os(iOS)
      RemoteAccessServing.setEnabled(true)
    #endif
    if let liftsAt = RappPairingBackoff.shared.nextOfferDate() {
      phase = .failed(.locked(until: liftsAt))
      scheduleOfferAfterLockout(liftsAt: liftsAt)
      return
    }
    let code = customCode.map(RappPairingCode.normalize) ?? RappPairingCode.generate()
    let custodianRelay = makeRelay()
    do {
      let newCoordinator = try RappPairingCoordinator.custodian(
        options: options(code: code), transport: makeTransport(relay: custodianRelay))
      pairingCode = code
      install(coordinator: newCoordinator, relay: custodianRelay)
      phase = .offer(code)
      Task { await newCoordinator.start() }
      custodianRelay.start()
    } catch {
      fail(.reported(String(localized: "Pairing could not be started")))
    }
  }

  /// The ceremony options both roles share; the offer hash binds them.
  internal func options(code: String) -> RappPairingCoordinator.Options {
    RappPairingCoordinator.Options(
      code: code,
      profiles: rappCredentialProfiles(),
      transportProfile: Self.ceremonyTransportProfile,
      displayName: Self.localDisplayName,
      platform: Self.localPlatform,
      vault: vault)
  }

  private func scheduleOfferAfterLockout(liftsAt: Date) {
    pairingTimeoutTask?.cancel()
    pairingTimeoutTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .seconds(max(0, liftsAt.timeIntervalSinceNow)))
      } catch {
        return
      }
      guard let self, case .failed = phase else { return }
      createOffer()
    }
  }

  internal func cancel() {
    resetAttempt()
  }

  /// Ends the ceremony the way its role calls for: a phone's own offer
  /// is followed by the next one, and a lockout shows until it lifts;
  /// a requester reports `failure`.
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
    return PairingRelay(displayName: String(localized: "RefineID iPhone")) { [weak self] event in
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
    reviewedPeerName = nil
    relay = nil
    relayGeneration = nil
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
      #if REFINEID_STREAM_TRANSPORT
        PhonePersistentTokenRelay.shared.refreshSessionRecord()
      #endif
    #endif
  }
}
