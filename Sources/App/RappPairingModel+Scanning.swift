// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import SwiftUI

/// The holder's half of the ceremony: entering an 8-character pairing code
/// and pairing with what it describes.
extension RappPairingModel {
  private static let defaultOfferLifetimeMilliseconds: UInt64 = 180_000
  private static let pairingTimeoutNanoseconds: UInt64 = 15_000_000_000

  internal func startCodeEntry() {
    resetAttempt()
    #if REFINEID_LOCAL_CARD && os(iOS)
      PhonePersistentTokenRelay.shared.suspendForPairing()
    #endif
    phase = .codeEntry
  }

  internal func acceptPairingCode(_ rawCode: String) {
    resetAttempt()
    #if REFINEID_LOCAL_CARD && os(iOS)
      PhonePersistentTokenRelay.shared.suspendForPairing()
    #endif
    let code = RappPairingCode.normalize(rawCode)
    guard RappPairingCode.isValid(code) else {
      fail(String(localized: "The pairing code is invalid or expired"))
      return
    }
    #if os(iOS)
      RemoteAccessServing.setEnabled(true)
    #endif
    do {
      let (_, uri) = try RappPairingCode.pairingOffer(
        for: code,
        profiles: RappApplePeerProfile.supportedCredentialProfiles,
        candidate: Self.offeredCandidate.binding,
        lifetimeMilliseconds: Self.defaultOfferLifetimeMilliseconds
      )
      beginPairing(uri, code: code)
      schedulePairingTimeout()
    } catch {
      fail(String(localized: "The pairing code is invalid or expired"))
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

  #if DEBUG
    /// Pairs with an offer URI directly.
    internal func acceptOfferWithoutScanning(_ uri: String, code: String) {
      resetAttempt()
      #if REFINEID_LOCAL_CARD && os(iOS)
        PhonePersistentTokenRelay.shared.suspendForPairing()
      #endif
      beginPairing(uri, code: code)
    }
  #endif

  private func beginPairing(_ uri: String, code: String) {
    phase = .connecting
    do {
      let candidates = try RappScannedOffer.candidates(scannedOfferURI: uri)
      if let applePeer = candidates.first(where: { candidate in
        candidate.profile == RappApplePeerProfile.name
      }) {
        try startApplePeerPairing(uri: uri, candidateID: applePeer.candidateID, code: code)
      } else if let stream = candidates.first(where: { candidate in
        candidate.profile == rappStreamProfileName() && !candidate.streamEndpoints.isEmpty
      }) {
        #if REFINEID_STREAM_TRANSPORT
          try startStreamPairing(
            uri: uri,
            candidateID: stream.candidateID,
            endpoints: stream.streamEndpoints,
            code: code
          )
        #else
          fail(String(localized: "The pairing code is invalid or expired"))
        #endif
      } else if let stream = candidates.first(where: { candidate in
        candidate.profile == rappStreamProfileName()
      }) {
        try startApplePeerPairing(uri: uri, candidateID: stream.candidateID, code: code)
      } else {
        fail(String(localized: "The pairing code is invalid or expired"))
      }
    } catch {
      fail(String(localized: "The pairing code is invalid or expired"))
    }
  }

  #if REFINEID_STREAM_TRANSPORT
    private func startStreamPairing(
      uri: String,
      candidateID: String,
      endpoints: [String],
      code: String
    ) throws {
      let relay = makeRelay(role: .cardHolder)
      let transport = makeTransport(relay: relay)
      #if os(macOS)
        let displayName = Host.current().localizedName ?? "Mac"
        let platform = "macOS"
      #else
        let displayName = UIDevice.current.name
        let platform = "iOS"
      #endif
      let coordinator = try RappPairingCoordinator.proxy(
        options: .init(
          scannedOfferURI: uri,
          selectedCandidateID: candidateID,
          displayName: displayName,
          platform: platform,
          vault: vault,
          transport: transport,
          code: code
        )
      )
      install(coordinator: coordinator, relay: relay)
      relay.start(dialingEndpoints: endpoints)
    }
  #endif

  private func startApplePeerPairing(uri: String, candidateID: String, code: String) throws {
    let relay = makeRelay(role: .cardHolder)
    let transport = makeTransport(relay: relay)
    #if os(macOS)
      let displayName = Host.current().localizedName ?? "Mac"
      let platform = "macOS"
    #else
      let displayName = UIDevice.current.name
      let platform = "iOS"
    #endif
    let coordinator = try RappPairingCoordinator.proxy(
      options: .init(
        scannedOfferURI: uri,
        selectedCandidateID: candidateID,
        displayName: displayName,
        platform: platform,
        vault: vault,
        transport: transport,
        code: code
      )
    )
    install(coordinator: coordinator, relay: relay)
    relay.start(sharingOfferURI: uri)
  }
}
