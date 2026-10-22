// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)
  import CardCore
  import CryptoKit
  import CryptoTokenKit
  import Foundation
  import Observation
  import RappEngine
  import Security

  /// Publishes the paired phone's authentication certificate as a per-user
  /// persistent CryptoTokenKit identity once the phone confirms that card
  /// (RAPP v26.10.22 §8.4).
  ///
  /// Private-key operations stay delegated to the phone. The identity is
  /// offered on a certificate whose fingerprint the phone confirmed on a
  /// session, and stays offered between sessions: a request with no session
  /// open dials the phone itself. It leaves at once when a session names
  /// another card, when the pairing is forgotten or revoked, and when the
  /// phone announces it stopped serving; otherwise once no session has
  /// reported the card present for ``RemoteIdentityOffer/grace``.
  @MainActor
  @Observable
  internal final class PersistentTokenRegistry {
    // MARK: Static Properties

    internal static let shared = PersistentTokenRegistry()

    internal static var isRemoteCardEnabled: Bool {
      #if REFINEID_REMOTE_CARD
        true
      #else
        false
      #endif
    }

    /// Whether a presence browser reports the holder in this build.
    internal static var browsesForPresence: Bool {
      #if REFINEID_STREAM_TRANSPORT
        true
      #else
        false
      #endif
    }

    internal static let fetchStateDidChangeNotification = Notification.Name(
      "fi.refineid.PersistentTokenRegistry.fetchStateDidChange"
    )

    // MARK: Static Computed Properties

    internal static var driverConfiguration: TKTokenDriver.Configuration? {
      TKTokenDriver.Configuration.driverConfigurations[
        PersistentTokenIdentity.classID
      ]
    }

    internal static var needsIdentity: Bool {
      guard let driver = driverConfiguration, !driver.tokenConfigurations.isEmpty else {
        return true
      }
      return driver.tokenConfigurations.values.contains { $0.configurationData == nil }
    }

    /// Safari's chooser title, matching the local reader token.
    ///
    /// Both certificates on a card share one subject, so the label is the
    /// only field that names the PIN 1 identity in DVV's wording.
    internal static var authenticationLabel: String {
      CredentialLabels.name(for: .pin1)
    }

    /// What this device calls itself to the phone.
    internal static var displayName: String {
      #if os(macOS)
        String(localized: "RefineID Mac")
      #else
        String(localized: "RefineID iPad")
      #endif
    }

    /// The pair ID of the currently selected or active remote holder.
    internal static var activePairID: Data? {
      let vault = RappDeviceVault()
      let pairIDs = (try? vault.activePairIDs()) ?? []
      guard !pairIDs.isEmpty else { return nil }
      return (try? vault.selectedPairID()) ?? pairIDs.first
    }

    // MARK: Properties

    /// Who the borrowed certificate names, for the identity row.
    internal var holderLine: String?

    /// The certificate last published, so a reader mint can restore it.
    internal var certificateDER: Data?

    /// Whether a certificate read is in flight.
    internal private(set) var isRunning = false
    internal var fetchBackoff = CertificateFetchBackoff()

    /// When the current unbroken run of failed (re)dials began.
    ///
    /// Nil when the last attempt produced a usable session. Bounds the
    /// redial loop (R-58): past the deadline it stops rather than dialing
    /// forever.
    internal var continuousFailureSince: ContinuousClock.Instant?

    /// Whether the presence browser reports the holder on the network now.
    ///
    /// Only the browser sets it. It decides whether to dial; an open
    /// session and the offered identity do not depend on it (§4.5 item 6).
    internal var holderIsAdvertising = false

    /// The phone's last `card.status` on the open session; absent without
    /// a session.
    internal var holderCardStatus = RappCardStatus.absent

    /// Whether the open session's last `card.status` says the phone holds
    /// no card; false without a session or before its first report.
    internal var holderReportsNoCard = false

    /// The paired phone, by the name it introduced itself with; nil
    /// while no phone is paired.
    internal private(set) var pairedPhone: String?

    /// The phone that told this computer it forgot it (RAPP v26.10.22 §4.6
    /// item 4), by name, until a phone is paired again.
    internal var phoneThatForgot: String?

    #if REFINEID_STREAM_TRANSPORT
      internal var presence: StreamRelayPresence?

      /// Marks the holder gone from the network after Bonjour has
      /// omitted it for ``advertisementLossHold``.
      internal var advertisementLossTask: Task<Void, Never>?
      internal var pairingsObservers: [any NSObjectProtocol] = []

      /// The standing session with the phone, while one is open.
      internal var holderSession: RappHeldRequesterSession?

      /// Names the open session, so a report from one this registry
      /// already let go is not taken for the current one's.
      internal var holderSessionToken: UUID?

      /// The pairing whose hint the phone on the network carries; a session
      /// dials it and no other (RAPP v26.10.22 §4.6 item 2).
      internal var pairInSight: Data?

      /// Dials the phone again after a session ended while it stayed on
      /// the network.
      internal var redialTask: Task<Void, Never>?

      /// Whether the phone still confirms the offered card (§8.4 item 3).
      internal var identityOffer = RemoteIdentityOffer(unconfirmedSince: .now)

      /// Withdraws the identity once ``identityOffer`` has lapsed.
      internal var offerLapseTask: Task<Void, Never>?
    #endif

    // MARK: Lifecycle

    private init() {
      // singleton
    }

    // MARK: Static Functions

    /// Withdraws every identity this driver has published.
    ///
    /// The published certificate is what Safari offers, so an identity the
    /// holder has dropped has to leave the registry too; leaving it there
    /// would keep offering a card this device can no longer reach.
    internal static func withdraw() {
      withdrawPublishedIdentity()
    }

    /// Removes the published identity.
    ///
    /// The pairing and the session are separate: a card leaving the phone
    /// withdraws the borrowed certificate and leaves both so the next
    /// card can use them.
    internal static func withdrawPublishedIdentity() {
      if let driver = driverConfiguration {
        for instanceID in driver.tokenConfigurations.keys {
          driver.removeTokenConfiguration(for: instanceID)
        }
      }
      shared.holderLine = nil
      shared.certificateDER = nil
      #if os(macOS)
        LoginIdentityModel.shared.refresh()
      #endif
    }

    // MARK: Functions

    /// Reads which phone is paired, for the identity row.
    internal func refreshPairing() {
      pairedPhone =
        Self.isRemoteCardEnabled
        ? Self.activePairID.map(RappPairNames.displayName(forPairID:)) : nil
      if pairedPhone != nil {
        phoneThatForgot = nil
      }
    }

    /// Starts following the paired phone at launch on the requesting
    /// device.
    internal func start() {
      refreshPairing()
      guard Self.isRemoteCardEnabled else {
        Self.withdrawPublishedIdentity()
        return
      }
      if CardPresence.shared.isReaderCardPresent {
        Self.withdrawPublishedIdentity()
        _ = DriverConfiguredCredentials.dropDisplacedRemoteCardConfigurations()
        return
      }
      let hasPairs = (try? RappDeviceVault().activePairIDs().isEmpty == false) ?? false
      guard hasPairs else {
        Self.withdrawPublishedIdentity()
        return
      }
      // An identity left behind by an earlier launch has no session
      // behind it; the phone's own word brings it back.
      Self.withdrawPublishedIdentity()
      fetchBackoff.reset()
      continuousFailureSince = nil
      #if REFINEID_STREAM_TRANSPORT
        installPairingObservers()
        startWatchingPresence()
      #else
        readCertificateOnce()
      #endif
    }

    /// Follows the phone after a pairing, replacing any identity a
    /// previous pair left behind.
    internal func startAfterPairing() {
      refreshPairing()
      guard Self.isRemoteCardEnabled else {
        Self.withdrawPublishedIdentity()
        return
      }
      Self.withdrawPublishedIdentity()
      if CardPresence.shared.isReaderCardPresent {
        return
      }
      fetchBackoff.reset()
      continuousFailureSince = nil
      #if REFINEID_STREAM_TRANSPORT
        closeHolderSession()
        restartWatchingPresence()
      #else
        readCertificateOnce()
      #endif
    }

    #if !REFINEID_STREAM_TRANSPORT
      /// Reads the certificate once over the nearby relay, which carries
      /// no standing session.
      private func readCertificateOnce() {
        guard !isRunning else { return }
        let hasPairs = (try? RappDeviceVault().activePairIDs().isEmpty == false) ?? false
        guard hasPairs else { return }
        beginRead()
        Task.detached(priority: .userInitiated) {
          let fetched: Data?
          do {
            let response = try RappPersistentRequesterClient(
              displayName: Self.displayName
            ).perform(.readAuthenticationCertificate)
            if case .authenticationCertificate(let certificate) = response {
              fetched = certificate
            } else {
              fetched = nil
            }
          } catch {
            fetched = nil
          }
          await Self.shared.finishRead(fetched)
        }
      }
    #endif

    /// Marks a certificate read as in flight.
    internal func beginRead() {
      isRunning = true
      NotificationCenter.default.post(
        name: Self.fetchStateDidChangeNotification, object: nil)
    }

    /// Takes what a certificate read produced; a certificate is offered,
    /// a failure is counted for the next attempt.
    internal func finishRead(_ fetched: Data?) {
      defer {
        isRunning = false
        NotificationCenter.default.post(
          name: Self.fetchStateDidChangeNotification, object: nil)
      }
      guard let fetched else {
        fetchBackoff.recordFailure(at: .now)
        #if REFINEID_STREAM_TRANSPORT
          retryReadAfterFailure()
        #endif
        return
      }
      // Only the card the phone names on this session is offered (RAPP
      // v26.10.22 §8.4 item 2); a certificate read across a card change
      // waits for the phone's next word.
      guard case .present(let named) = holderCardStatus,
        RappCertificateFingerprint(certificate: fetched) == named
      else { return }
      switch Self.publish(fetched) {
      case .notPublished:
        fetchBackoff.recordFailure(at: .now)

      case .readerHasPriority, .published:
        fetchBackoff.reset()
      }
    }
  }
#endif
