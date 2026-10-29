// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation
  import os
  import RappEngine

  #if DEBUG
    /// The event's case name alone, which is what a timeline needs.
    internal func eventCaseName(_ event: RappConnectionCoordinator.Event) -> String {
      String(describing: event).prefix { $0 != "(" }.description
    }
  #endif

  /// Owns the phone side of RAPP: every session the paired computers open,
  /// and the one queue their operations take the card through (RAPP
  /// v26.10.29 §8.2 item 2, §8.3).
  ///
  /// Each routed connection is a session of its own, on the stream
  /// listener, the Bluetooth server, or, in a build without the stream, the
  /// nearby relay; an open session is never a reason to refuse, hold or
  /// displace another (STPA CC-58). The transports are opaque frame
  /// carriers; all identity, sequencing, operation, and fail-stop decisions
  /// belong to RAPP.
  @MainActor
  internal final class PhonePersistentTokenRelay: ObservableObject {
    // MARK: Static Properties

    internal static let shared = PhonePersistentTokenRelay()

    // MARK: Properties

    internal let vault = RappDeviceVault()
    private let policy = RappRequesterPolicy.interactive
    private var pairingsObserver: (any NSObjectProtocol)?
    /// The sessions open now, by their own identifier.
    internal var sessions: [UUID: ServedSession] = [:]
    /// Hands the card to one operation at a time, across every session.
    internal let cardQueue = CustodianCardQueue<ServedSession.Turn>()
    /// What this phone knows of the reader card it serves.
    internal var readerCard = ReaderCard()
    /// What each open session was last told in `card.status`.
    internal var cardReports = CardStatusReports<UUID>()
    /// Sweeps the pairings for idle expiry while the app runs.
    internal let idleSweep = PairingIdleSweep()
    #if REFINEID_STREAM_TRANSPORT
      /// The session listener, while the phone serves the stream.
      internal var sessionListener: StreamSessionListener?
      /// Takes the listener's events on the main actor, in order.
      internal var sessionListenerEvents: Task<Void, Never>?
      internal var sessionListening = SessionListening()
      /// The GATT server, while the phone serves over Bluetooth.
      internal var bluetoothServer: RappBleGattPeripheral?
      /// Takes the server's events on the main actor, in order.
      internal var bluetoothEvents: Task<Void, Never>?
      /// The pairings and replay memory the server's queue routes links
      /// with, and the pairing each admitted link routed to.
      nonisolated internal let bluetoothRouting = OSAllocatedUnfairLock(
        initialState: BluetoothRouting())
      /// Whether the server advertises now.
      internal var bluetoothAdvertising = false
      /// Whether the stream listener stays down while the app is in the
      /// background (CC-68).
      internal var streamSuspended = false
      /// Observes the app entering and leaving the background.
      internal var lifecycleObservers: [any NSObjectProtocol] = []
    #else
      /// The nearby relay, while the phone serves it.
      internal var relay: PersistentRelaySession?
      /// Names the nearby connection, so a report from an earlier one is
      /// dropped.
      internal var nearbyConnectionID: UUID?
      /// Frames the nearby connection delivered before its session started.
      internal var preCoordinatorFrames: [Data] = []
    #endif
    @Published internal var isActivelyConnected = false {
      didSet { connectionIndicator.update(active: isActivelyConnected) }
    }

    /// Whether a paired requester is shown as connected.
    @Published internal private(set) var isPeerConnected = false

    private lazy var connectionIndicator = ConnectionIndicator(
      hold: ConnectionIndicator.defaultHold
    ) {
      [weak self] shown in
      self?.isPeerConnected = shown
    }

    // MARK: Lifecycle

    private init() {
      pairingsObserver = NotificationCenter.default.addObserver(
        forName: RappAutoPairingService.pairingsDidChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.start()
        }
      }
      ReaderTokenPublication.shared.onPublished {
        Task { @MainActor in
          Self.shared.prepareReaderCard()
        }
      }
      #if REFINEID_STREAM_TRANSPORT
        observeLifecycle()
      #endif
    }

    // MARK: Functions

    internal func start() {
      // Remote serving is opt-in: without the holder's choice nothing
      // advertises, so no local-network prompt can surprise them.
      guard RemoteAccessGate.isEnabled else { return }
      // A proxy without an antenna is not a proxy: only near-field
      // devices advertise as the card holder.
      guard SupportedCardTransports.offersNearField else { return }
      #if REFINEID_STREAM_TRANSPORT
        guard hasUsablePair() else { return }
        let contexts = PhoneStreamPairContext.resolveAll(vault: vault)
        guard !contexts.isEmpty else { return }
        startBluetoothServing(contexts)
        guard !streamSuspended else { return }
        startListening(contexts)
      #else
        startNearby()
      #endif
    }

    /// Opens the session a routed connection carries, over `pair`.
    ///
    /// `frames` carries the session's frames on `transport`; nil when the
    /// session could not be made, and the caller drops the connection.
    @discardableResult
    internal func openSession(
      pair: RappPairRecord,
      on transport: ServedTransport,
      transportProfile: String,
      frames: RappClosureFrameTransport,
      earlyFrames: [Data]
    ) -> ServedSession? {
      let coordinator: RappConnectionCoordinator
      do {
        coordinator = try RappConnectionCoordinator(
          role: .proxy,
          pair: pair,
          transport: frames,
          maximumLifetimeMilliseconds: policy.maximumOperationLifetimeMilliseconds,
          transportProfile: transportProfile)
      } catch {
        #if DEBUG
          DevErrorLog.report("session not started: \(DevErrorLog.reason(error))", source: .app)
        #endif
        return nil
      }
      let session = ServedSession(
        transport: transport, pairID: pair.metadata().pairId, coordinator: coordinator,
        cardQueue: cardQueue
      ) { [weak self] session, report in
        self?.sessionReported(session, report)
      }
      sessions[session.identifier] = session
      isActivelyConnected = true
      PairLastUse.markUsed(pairID: session.pairID, at: Date())
      session.start(earlyFrames: earlyFrames)
      return session
    }

    /// The open session on `transport`, if any.
    internal func session(on transport: ServedTransport) -> ServedSession? {
      sessions.values.first { $0.transport == transport }
    }

    /// Acts on what one session reports.
    private func sessionReported(_ session: ServedSession, _ report: ServedSession.Report) {
      switch report {
      case .established:
        PersistentTokenRegistry.recordSession(pairID: session.pairID)
        // The custodian's first word on a session is which card it holds
        // and whether a reader is connected (§8.4); the requester offers
        // nothing before it.
        cardReports.forget(session.identifier)
        reportCardStatus(to: session)
        prepareReaderCard()

      case .operationOver:
        #if REFINEID_STREAM_TRANSPORT
          suspendStreamWhenIdle()
        #endif

      case .frameOverrun:
        #if DEBUG
          DevErrorLog.report("session dropped: frames outran the delivery queue", source: .app)
        #endif
        dropTransport(of: session)
        session.transportClosed()

      case .closed(let reason):
        sessionClosed(session, reason: reason)
      }
    }

    /// Forgets a session that ended, and the pairing when its close ended
    /// that too.
    private func sessionClosed(
      _ session: ServedSession, reason: RappConnectionCoordinator.CloseReason
    ) {
      #if DEBUG
        if let failure = reason.devErrorName(midOperation: !session.isIdle) {
          DevErrorLog.report("session closed: \(failure)", source: .app)
        }
      #endif
      guard sessions.removeValue(forKey: session.identifier) != nil else { return }
      cardReports.forget(session.identifier)
      if session.isEstablished {
        PersistentTokenRegistry.recordSession(pairID: session.pairID)
      }
      endPairingIfOver(reason, pairID: session.pairID)
      if sessions.isEmpty {
        isActivelyConnected = false
        Task {
          await RappReaderSessionHolder.shared.close()
          await RappNearFieldSessionHolder.shared.closeSession(.lastSessionClosed)
        }
      }
      if !hasUsablePair() {
        tearDownTransport()
        return
      }
      #if REFINEID_STREAM_TRANSPORT
        suspendStreamWhenIdle()
      #endif
    }

    /// Ends the connection under `session`: its stream connection, its
    /// Bluetooth link, or the nearby relay.
    internal func dropTransport(of session: ServedSession) {
      switch session.transport {
      #if REFINEID_STREAM_TRANSPORT
        case .stream(let connection):
          sessionListener?.disconnect(connection)

        case .bluetooth(let link):
          bluetoothServer?.close(link)
      #else
        case .nearby:
          relay?.cancel()
      #endif
      }
    }

    /// Sweeps every pairing for idle expiry (RAPP v26.10.29 §4.6 item 5): a
    /// computer a session is established with is recorded, and one with
    /// none for 30 days expires silently and leaves the paired computers.
    internal func sweepIdlePairings() {
      let established = Set(
        sessions.values.filter { $0.isEstablished && !$0.hasEnded }.map(\.pairID))
      let sweep = RappPairIdleExpiry.sweep(
        in: vault, nowMilliseconds: RappPlatformClock().wallMilliseconds(),
        established: established)
      #if DEBUG
        if sweep.failures > 0 {
          DevErrorLog.report(
            "pairing idle expiry: \(sweep.failures) pairing(s) not swept", source: .app)
        }
      #endif
      guard !sweep.expired.isEmpty else { return }
      NotificationCenter.default.post(
        name: RappPairingModel.pairingsDidChangeNotification, object: nil)
    }

    /// Destroys the pairing `pairID` when the session's close ended it: the
    /// requester revoked it, or this phone delivered the close of a pairing
    /// its holder forgot (RAPP v26.10.29 §4.6 items 2 to 4).
    private func endPairingIfOver(_ reason: RappConnectionCoordinator.CloseReason, pairID: Data) {
      guard reason.peerRevokedPairing || reason == .handshake(.revocationNoticeDelivered) else {
        return
      }
      try? RappPairRevocation.revoke(pairID: pairID, in: vault, clock: RappPlatformClock())
      RappPairNames.forget(pairID: pairID)
      NotificationCenter.default.post(
        name: RappPairingModel.pairingsDidChangeNotification, object: nil)
    }
  }
#endif
