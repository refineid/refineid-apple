// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation
  import Network
  import os
  import RappEngine
  /// Owns the phone side of one mutually authenticated RAPP connection.
  ///
  /// The transport is an opaque frame carrier chosen by the selected pair:
  /// MultipeerConnectivity advertises nearby, while the stream profile dials
  /// the requester's stored listener endpoints. All identity, sequencing,
  /// operation, and fail-stop decisions belong to RAPP.
  #if DEBUG
    /// The event's case name alone, which is what a timeline needs.
    internal func eventCaseName(_ event: RappConnectionCoordinator.Event) -> String {
      String(describing: event).prefix { $0 != "(" }.description
    }
  #endif

  @MainActor
  internal final class PhonePersistentTokenRelay: ObservableObject {
    // MARK: Static Properties

    internal static let shared = PhonePersistentTokenRelay()

    internal static let maximumPreCoordinatorFrames = 4
    internal static let nearbyRedialDelayMilliseconds = 150

    // MARK: Properties

    internal let vault = RappDeviceVault()
    private let policy = RappRequesterPolicy.interactive
    private var pairingsObserver: (any NSObjectProtocol)?
    internal var relay: PersistentRelaySession?
    #if REFINEID_STREAM_TRANSPORT
      internal var streamListeners: [String: StreamRelayListener] = [:]
      internal var activeStreamListener: StreamRelayListener?
      internal var sessionListening = SessionListening()
      /// The transport the open session runs over.
      internal var servedTransport: ServedTransport?
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
    #endif
    internal var coordinator: RappConnectionCoordinator?
    internal var dispatcher: RappPhoneProxyDispatcher?
    /// The pairing the open session serves and when it last went idle,
    /// as one value so the listener's queue reads a consistent snapshot.
    ///
    /// `idleSince` is nil while an operation is in flight (never
    /// displace a busy session) and while a handshake is still coming
    /// up; `pairing` names the requester so its own app and token
    /// extension hand the session over at once, a different one waits
    /// out the hold (R-59).
    nonisolated internal let sessionServing = OSAllocatedUnfairLock<
      (pairing: Data?, idleSince: ContinuousClock.Instant?)
    >(initialState: (nil, nil))
    /// The pairings a dialer may displace an idle session for, read on
    /// the listener's queue with its own replay memory.
    nonisolated internal let replacementRouting = OSAllocatedUnfairLock<
      (records: [RappPairRecord], router: RappSessionRouter)
    >(initialState: ([], RappSessionRouter()))
    /// The operations the open session is running.
    internal var operationsInFlight: Set<RappOperationIdentifier> = []
    /// What the open session was last told about the card.
    internal var reportedCardStatus: RappCardStatus?
    /// What this phone knows of the reader card it serves.
    internal var readerCard = ReaderCard()
    /// The pairing the open session runs over.
    internal var activePairID: Data?
    internal var connectionID: UUID?
    internal var preCoordinatorFrames: [Data] = []
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

    /// Frames enter the coordinator in arrival order through this
    /// bounded chain; reset between connections.
    internal let frameDelivery = OrderedDelivery(
      capacity: OrderedDelivery.relayFrameCapacity)

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
        pruneStreamTransports(keeping: streamKeys(for: contexts))
        startListening(contexts)
      #else
        guard relay == nil, coordinator == nil,
          hasUsableSelectedPair()
        else { return }
        let nearbyConnectionID = UUID()
        let nearby = PersistentRelaySession(
          role: .cardHolder,
          displayName: "RefineID iPhone"
        ) { [weak self] event in
          Task { @MainActor in
            self?.receive(event, connectionID: nearbyConnectionID)
          }
        }
        connectionID = nearbyConnectionID
        relay = nearby
        nearby.start()
      #endif
    }

    private func receive(
      _ event: PersistentRelayEvent,
      connectionID: UUID
    ) {
      guard self.connectionID == connectionID else { return }
      switch event {
      case .connected:
        establish(connectionID: connectionID)

      case .frame(let frame):
        if let coordinator {
          deliverInOrder { await coordinator.receive(frame) }
        } else if preCoordinatorFrames.count < Self.maximumPreCoordinatorFrames {
          preCoordinatorFrames.append(frame)
        } else {
          relay?.cancel()
        }

      case .closed:
        handleTransportClosed(redialDelayMilliseconds: Self.nearbyRedialDelayMilliseconds)
      }
    }

    private func establish(connectionID: UUID) {
      guard self.connectionID == connectionID, coordinator == nil,
        let relay
      else { return }

      let transport = RappClosureFrameTransport(
        sender: { [weak relay] frame in
          guard let relay else {
            throw PersistentRelayTransportError.disconnected
          }
          try relay.send(frame)
        },
        closer: { [weak relay] in relay?.cancel() }
      )
      establishCoordinator(
        connectionID: connectionID,
        transport: transport
      ) { [weak relay] in
        relay?.cancel()
      }
    }

    internal func establishCoordinator(
      connectionID: UUID,
      transport: RappClosureFrameTransport,
      failTransport: () -> Void
    ) {
      establishCoordinator(
        connectionID: connectionID,
        pair: nil,
        transportProfile: rappStreamProfileName(),
        transport: transport,
        failTransport: failTransport
      )
    }

    internal func establishCoordinator(
      connectionID: UUID,
      pair explicitPair: RappPairRecord?,
      transportProfile: String,
      transport: RappClosureFrameTransport,
      failTransport: () -> Void
    ) {
      do {
        let pair: RappPairRecord
        if let explicitPair {
          pair = explicitPair
        } else if let resolved = try PhoneProxyPairSelection.resolveSelectedPair(vault: vault) {
          pair = resolved
        } else {
          failTransport()
          return
        }
        let made = try RappConnectionCoordinator(
          role: .proxy,
          pair: pair,
          transport: transport,
          maximumLifetimeMilliseconds:
            policy.maximumOperationLifetimeMilliseconds,
          transportProfile: transportProfile
        )
        let madeDispatcher = RappPhoneProxyDispatcher(
          inbox: RappAuthorizationInbox.shared
        )
        coordinator = made
        dispatcher = madeDispatcher
        activePairID = pair.metadata().pairId
        sessionServing.withLock { $0 = (pair.metadata().pairId, nil) }
        isActivelyConnected = true

        let earlyFrames = preCoordinatorFrames
        preCoordinatorFrames.removeAll(keepingCapacity: false)
        pumpEvents(
          from: made,
          dispatcher: madeDispatcher,
          connectionID: connectionID,
          earlyFrames: earlyFrames
        )
      } catch {
        #if DEBUG
          DevErrorLog.report("session not started: \(DevErrorLog.reason(error))", source: .app)
        #endif
        failTransport()
      }
    }

    private func pumpEvents(
      from coordinator: RappConnectionCoordinator,
      dispatcher: RappPhoneProxyDispatcher,
      connectionID: UUID,
      earlyFrames: [Data]
    ) {
      Task { [weak self] in
        for await event in coordinator.events {
          await dispatcher.receive(event, from: coordinator)
          self?.observe(event, connectionID: connectionID)
        }
      }
      // The replay joins the same chain later frames append to, so a
      // frame arriving during the replay cannot overtake it.
      deliverInOrder {
        await coordinator.start()
        for frame in earlyFrames {
          await coordinator.receive(frame)
        }
      }
    }

    /// Runs `work` after every delivery enqueued before it, cancelling a
    /// transport whose peer outruns the bounded chain.
    internal func deliverInOrder(_ work: @escaping @Sendable () async -> Void) {
      if frameDelivery.deliver(work) { return }
      #if DEBUG
        print("[stream-holder] deliverInOrder rejected! cancelling transport")
        fflush(stdout)
        DevErrorLog.report("session dropped: frames outran the delivery queue", source: .app)
      #endif
      relay?.cancel()
      #if REFINEID_STREAM_TRANSPORT
        dropServedTransport()
      #endif
    }
  }
#endif
