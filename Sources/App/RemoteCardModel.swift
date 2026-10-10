// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import CardCore
  import Foundation
  import SwiftUI

  /// The requester's view of the selected remote card.
  ///
  /// Connecting asks the paired card holder for the authentication
  /// certificate; the holder approves the request and presents the card.
  /// The certificate's subject then names the person on this screen.
  @MainActor
  internal final class RemoteCardModel: ObservableObject {
    internal enum Phase: Equatable {
      case idle
      case connecting
      case identity(String)
      case failed
    }

    @Published internal private(set) var phase = Phase.idle

    /// Why the last attempt failed, in the holder's words.
    @Published internal private(set) var failureText: String?

    /// Whether a requester pairing exists to connect through.
    @Published internal private(set) var hasPair = false

    /// Whether the stored pairing turned out to be one the peer no longer
    /// honours, so the only way forward is a fresh code.
    @Published internal private(set) var needsFreshPairing = false

    /// The person shown once the remote card has answered.
    internal var holder: String? {
      if case .identity(let holder) = phase { return holder }
      return nil
    }

    /// Re-reads the selected pairing and establishes a live connection.
    internal func refresh() {
      #if DEBUG
        // A stored pairing is what makes this device believe it can just
        // reconnect. A test needs that belief without two devices and a
        // scanned code, because the rule under test is what the belief
        // makes the screen do.
        if ProcessInfo.processInfo.arguments.contains("--pretend-paired") {
          hasPair = true
          return
        }
      #endif
      Task {
        let catalog = RappPairCatalog(vault: RappDeviceVault())
        let selected = try? await catalog.selectedPair()
        hasPair = selected?.role == .requester
        if !hasPair {
          PersistentTokenRegistry.withdraw()
          phase = .idle
        } else if holder == nil {
          connect()
        }
      }
    }

    /// Re-reads the selected pairing and, when one is there, uses it.
    internal func refreshThenConnect() {
      Task {
        let catalog = RappPairCatalog(vault: RappDeviceVault())
        let selected = try? await catalog.selectedPair()
        hasPair = selected?.role == .requester
        if !hasPair {
          PersistentTokenRegistry.withdraw()
          phase = .idle
        } else {
          connect()
        }
      }
    }

    /// Reads the holder from the remote card's authentication
    /// certificate.
    internal func connect() {
      guard phase != .connecting else { return }
      phase = .connecting
      Task.detached(priority: .userInitiated) { [weak self] in
        await self?.performConnect()
      }
    }

    private func performConnect() async {
      let response: RappRequesterResponse?
      var failure: String?
      do {
        response = try RappPersistentRequesterClient(
          displayName: String(localized: "RefineID iPad")
        ).perform(.readAuthenticationCertificate)
      } catch let error as RappRequesterClientError {
        response = nil
        failure = remoteFailureText(for: error)
        if error.leavesPairingUnusable {
          await discardUnusablePairing()
        }
      } catch {
        response = nil
        failure = String(localized: "The remote card could not be read.")
      }
      await MainActor.run {
        setFailureText(failure)
        if case .authenticationCertificate(let der, let cardSerial) = response,
          let name = remoteHolderName(inCertificate: der)
        {
          #if DEBUG
            print("[RemoteCardModel] publish: publishing certificate for holder=\(name)")
            fflush(stdout)
          #endif
          PersistentTokenRegistry.publish(der, cardSerial: cardSerial)
          finishConnect(holder: name)
        } else {
          #if DEBUG
            print("[RemoteCardModel] publish: no authentication certificate response or name")
            fflush(stdout)
          #endif
          finishConnect(holder: nil)
        }
      }
    }

    private func finishConnect(holder: String?) {
      #if DEBUG
        print("[RemoteCardModel] finishConnect: holder=\(String(describing: holder))")
        fflush(stdout)
      #endif
      if let holder {
        phase = .identity(holder)
        failureText = nil
      } else if self.holder == nil {
        phase = .failed
      }
    }

    private func setFailureText(_ text: String?) {
      failureText = text
    }

    /// Drops a pairing the peer no longer honours and asks for a fresh one.
    private func discardUnusablePairing() async {
      let catalog = RappPairCatalog(vault: RappDeviceVault())
      if let pairs = try? await catalog.activePairs() {
        for pair in pairs {
          try? await catalog.revoke(pairID: pair.pairID)
        }
      }
      try? await catalog.clearSelection()
      await MainActor.run {
        PersistentTokenRegistry.withdraw()
        hasPair = false
        phase = .idle
        needsFreshPairing = true
      }
    }

    /// Clears the request once the caller has shown a code.
    internal func acknowledgeFreshPairing() {
      needsFreshPairing = false
    }

    /// Drops the borrowed identity and the pairing it came through.
    ///
    /// The identity on this screen is someone else's card, reached through
    /// a pairing; letting go of the person means letting go of the pairing,
    /// or the next connect would silently bring the same one back.
    internal func forget() {
      phase = .idle
      failureText = nil
      hasPair = false
      PersistentTokenRegistry.withdraw()
      Task {
        let catalog = RappPairCatalog(vault: RappDeviceVault())
        if let pairs = try? await catalog.activePairs() {
          for pair in pairs {
            try? await catalog.revoke(pairID: pair.pairID)
          }
        }
        try? await catalog.clearSelection()
      }
    }
  }

  extension RappRequesterClientError {
    /// Whether this failure means the stored pairing can no longer serve.
    ///
    /// A peer that never answers and a pairing the vault cannot resolve are
    /// both dead ends for the record on this device; anything else may be
    /// worth another attempt with the same pairing.
    fileprivate var leavesPairingUnusable: Bool {
      switch self {
      case .noActivePair, .noSelectedPair, .terminal, .protocolFailure:
        true

      case .peerNotFound, .timedOut, .transport, .unexpectedResult:
        // A phone that could not be reached says nothing about whether the
        // pairing is good. Discarding it here would make a network away
        // from home cost the holder their pairing.
        false
      }
    }
  }

  /// The cardholder line an answered certificate yields, or nil when the
  /// subject carries no name this app can show.
  private func remoteHolderName(inCertificate der: Data) -> String? {
    DistinguishedName.holderLine(fromCertificate: der)
  }

  /// Names the failure so the holder knows which device to attend to.
  private func remoteFailureText(for error: RappRequesterClientError) -> String {
    switch error {
    case .noActivePair, .noSelectedPair:
      String(localized: "No paired phone. Pair a phone to use its card.")

    case .peerNotFound:
      String(
        localized:
          """
          No paired phone found. Check both devices share a Wi-Fi network, \
          and that Local Network is allowed for RefineID in Settings.
          """)

    case .timedOut:
      String(localized: "The phone did not answer. Open RefineID on the phone and try again.")

    default:
      String(localized: "The remote card could not be read.")
    }
  }

#endif
