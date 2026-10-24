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
  /// another card, when the pairing is forgotten or revoked, when the
  /// phone announces it stopped serving, and when remote use is turned off;
  /// otherwise once no session has reported the card present for
  /// ``RemoteIdentityOffer/grace``. A pairing idle for 30 days expires
  /// silently (RAPP v26.10.22 §4.6 item 5).
  @MainActor
  @Observable
  internal final class PersistentTokenRegistry {
    // MARK: Static Properties

    internal static let shared = PersistentTokenRegistry()

    /// Whether this device follows a paired phone: a Mac, or an iPad with
    /// no card of its own.
    ///
    /// A device that serves its own card through near field is the phone
    /// end of every pairing; following its pairings would dial its own
    /// listener and refuse itself.
    internal static var dialsPhones: Bool {
      #if REFINEID_REMOTE_CARD
        !SupportedCardTransports.offersNearField
      #else
        false
      #endif
    }

    /// Whether this device reaches the phone over Bluetooth when Bonjour
    /// does not show it: a Mac, whose app holds the one link its token
    /// extension hands operations to.
    internal static var dialsOverBluetooth: Bool {
      #if os(macOS)
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

    /// Whether a session over Bluetooth is up with the phone.
    ///
    /// Bluetooth advertisements name no pairing (RAPP v26.10.22 §4.1), so
    /// over Bluetooth only an established session says the phone is there.
    internal var holderOverBluetooth = false

    /// Whether the paired phone is in sight: on the network, or holding a
    /// session over Bluetooth.
    internal var holderInSight: Bool {
      holderIsAdvertising || holderOverBluetooth
    }

    /// The phone's last `card.status` on the open session; nil without a
    /// session or before its first report.
    internal var holderCardStatus: RappCardStatus?

    /// How to ask for the phone's card, while the open session's last
    /// `card.status` says the phone holds none (RAPP v26.10.22 §8.4 item
    /// 6).
    internal var holderCardRequest: PhoneCardRequest? {
      PhoneCardRequest(holderCardStatus)
    }

    /// The paired phone's pairing; nil while no usable pairing exists.
    internal private(set) var pairedPhoneID: Data?

    /// The phone that told this computer it forgot it (RAPP v26.10.22 §4.6
    /// item 4), by name, until a phone is paired again.
    internal var phoneThatForgot: String?

    /// Whether the platform denied this app the local network on a dial
    /// to a phone, until a session is up, remote use stops, or the app is
    /// active again and tries afresh.
    internal var localNetworkDenied = false

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

      /// Dials the phone again once the wait after a session that ended is
      /// over.
      internal var redialTask: Task<Void, Never>?

      /// Whether the phone still confirms the offered card (§8.4 item 3).
      internal var identityOffer = RemoteIdentityOffer(unconfirmedSince: .now)

      /// Withdraws the identity once ``identityOffer`` has lapsed.
      internal var offerLapseTask: Task<Void, Never>?

      /// The one session this computer holds with the phone: whether it is
      /// being dialled or is up, over which transport, and when the next
      /// dial may go.
      internal var sessionSlot = RequesterSessionSlot()

      /// Whether Bonjour lists the phone's record this moment, without the
      /// hold ``holderIsAdvertising`` applies to a vanished one: a record
      /// gone for good sends the next dial over Bluetooth at once.
      internal var holderRecordListed = false

      /// Whether a stream dial failed since the phone last appeared on
      /// Bonjour (CC-72).
      internal var streamFailedInSight = false

      /// Whether Bluetooth may be dialed: not found off or refused to this
      /// app since the pairing or the phone's presence last changed.
      internal var bluetoothUsable = PersistentTokenRegistry.dialsOverBluetooth

      /// Which advertisers Bluetooth dials prefer and avoid (CC-53).
      internal var bluetoothPeers = RequesterBluetoothPeers()

      /// Dials once Bonjour has had its chance to show the phone.
      internal var settleDialTask: Task<Void, Never>?

    #endif

    #if os(macOS) && REFINEID_REMOTE_CARD
      /// The latest click off forgetting every pairing (RAPP v26.10.22 §4.6
      /// item 6), or one left unfinished tried again; nil once it finished
      /// and the app followed.
      internal var forgetting: Task<Void, Never>?

      /// The latest forgetting's destruction, off the main thread, which a
      /// quit waits on; nil once it finished.
      internal var pairingDestruction: Task<RemoteUseForgetting.Outcome, Never>?

      /// Counts the forgettings started; only the latest lets go of them.
      internal var forgettingGeneration = 0
    #endif

    /// Sweeps the pairings for idle expiry while the app runs.
    internal let idleSweep = PairingIdleSweep()

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

    /// Reads which phone `vault` pairs, for the identity row.
    internal func refreshPairing(in vault: RappDeviceVault) {
      pairedPhoneID = Self.dialsPhones ? Self.pairedPhoneID(in: vault) : nil
      if pairedPhoneID != nil {
        phoneThatForgot = nil
      }
    }

    /// Starts following the paired phone at launch on the requesting
    /// device, when remote use is turned on, and when a card leaves this
    /// device's reader.
    ///
    /// While a click off is forgetting the pairings, following waits until
    /// they are gone (RAPP v26.10.22 §4.6 item 6).
    internal func start() {
      #if os(macOS) && REFINEID_REMOTE_CARD
        guard forgetting == nil else { return }
      #endif
      refreshPairing()
      guard Self.followsPhone else {
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
        bluetoothUsable = Self.dialsOverBluetooth
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
      guard Self.followsPhone else {
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
        bluetoothUsable = Self.dialsOverBluetooth
        bluetoothPeers = RequesterBluetoothPeers()
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
    }

    /// Takes what a certificate read produced; a certificate is offered,
    /// a failure is counted for the next attempt.
    internal func finishRead(_ fetched: Data?) {
      defer { isRunning = false }
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
      guard case .present(let named)? = holderCardStatus?.card,
        RappCertificateFingerprint(certificate: fetched) == named
      else { return }
      switch Self.publish(fetched) {
      case .notPublished:
        #if DEBUG
          DevErrorLog.report("phone identity not published", source: .app)
        #endif
        fetchBackoff.recordFailure(at: .now)

      case .readerHasPriority, .remoteUseOff, .published:
        fetchBackoff.reset()
      }
    }
  }
#endif
