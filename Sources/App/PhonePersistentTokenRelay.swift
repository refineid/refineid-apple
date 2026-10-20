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
    /// How long the stream transport pauses before re-listening after a
    /// connection closes.
    internal static let streamRedialDelayMilliseconds = 100
    internal static let nearbyRedialDelayMilliseconds = 150

    /// Whether this phone can answer for a card now: a card in a
    /// connected reader, or a primed near-field card the holder can
    /// present when asked.
    internal static var canServeCard: Bool {
      CardPresence.shared.isReaderCardPresent || PrimeStore.storedCount() > 0
    }

    // MARK: Properties

    internal let vault = RappDeviceVault()
    private let policy = RappRequesterPolicy.interactive
    private var pairingsObserver: (any NSObjectProtocol)?
    internal var relay: PersistentRelaySession?
    #if REFINEID_STREAM_TRANSPORT
      internal var streamListeners: [String: StreamRelayListener] = [:]
      internal var activeStreamListener: StreamRelayListener?
      internal var sessionListening = SessionListening()
    #endif
    internal var coordinator: RappConnectionCoordinator?
    internal var dispatcher: RappPhoneProxyDispatcher?
    /// Whether the open session carries no operation, read on the
    /// listener's queue when another dialer arrives.
    nonisolated internal let sessionIsIdle = OSAllocatedUnfairLock(initialState: false)
    /// The pairings a dialer may displace an idle session for, read on
    /// the listener's queue with its own replay memory.
    nonisolated internal let replacementRouting = OSAllocatedUnfairLock<
      (records: [RappPairRecord], router: RappSessionRouter)
    >(initialState: ([], RappSessionRouter()))
    /// The operations the open session is running.
    internal var operationsInFlight: Set<Data> = []
    /// The word on the card the requester is given (RAPP v26.10.18 §8.4).
    internal var cardReport = CustodianCardReport(servable: canServeCard)
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
    }

    // MARK: Functions

    internal func start() {
      // Remote serving is opt-in: without the holder's choice nothing
      // advertises, so no local-network prompt can surprise them.
      guard RemoteAccessGate.isEnabled else { return }
      // A proxy without an antenna is not a proxy: only near-field
      // devices advertise as the card holder.
      guard SupportedCardTransports.offersNearField else { return }
      // A holder with no card has nothing to serve; advertising would
      // keep remotes offering an identity this phone can no longer sign.
      guard PrimeStore.storedCount() > 0 || CardPresence.shared.isReaderCardPresent
      else { return }
      #if REFINEID_STREAM_TRANSPORT
        guard coordinator == nil,
          hasUsablePair()
        else { return }
        let contexts = PhoneStreamPairContext.resolveAll(vault: vault)
        guard !contexts.isEmpty else { return }
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
          vault: vault,
          transport: transport,
          maximumLifetimeMilliseconds:
            policy.maximumOperationLifetimeMilliseconds,
          liveness: policy.liveness,
          transportProfile: transportProfile
        )
        let madeDispatcher = RappPhoneProxyDispatcher(
          inbox: RappAuthorizationInbox.shared
        )
        coordinator = made
        dispatcher = madeDispatcher
        activePairID = pair.metadata().pairId
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

    /// Serves a session the caller's transport routed by its preamble.
    ///
    /// Returns the connection's identifier, or nil when another session is
    /// open or the session cannot start.
    internal func serveRoutedSession(
      pair: RappPairRecord,
      transportProfile: String,
      transport: RappClosureFrameTransport,
      failTransport: () -> Void
    ) -> UUID? {
      guard coordinator == nil else { return nil }
      let routedConnectionID = UUID()
      connectionID = routedConnectionID
      PairLastUse.markUsed(pairID: pair.metadata().pairId, at: Date())
      establishCoordinator(
        connectionID: routedConnectionID, pair: pair, transportProfile: transportProfile,
        transport: transport, failTransport: failTransport)
      guard coordinator != nil else {
        connectionID = nil
        return nil
      }
      return routedConnectionID
    }

    /// Delivers one frame of a routed session in order, calling `overflow`
    /// when the peer outruns the bounded chain.
    internal func receiveRoutedFrame(
      _ frame: Data, connectionID routedConnectionID: UUID, overflow: () -> Void
    ) {
      guard connectionID == routedConnectionID, let coordinator else { return }
      if !frameDelivery.deliver({ await coordinator.receive(frame) }) {
        overflow()
      }
    }

    /// Ends a routed session whose transport closed.
    internal func routedSessionClosed(connectionID routedConnectionID: UUID) {
      guard connectionID == routedConnectionID else { return }
      handleConnectionClosed()
    }

    /// Runs `work` after every delivery enqueued before it, cancelling a
    /// transport whose peer outruns the bounded chain.
    internal func deliverInOrder(_ work: @escaping @Sendable () async -> Void) {
      if frameDelivery.deliver(work) { return }
      #if DEBUG
        print("[stream-holder] deliverInOrder rejected! cancelling transport")
        fflush(stdout)
      #endif
      relay?.cancel()
      #if REFINEID_STREAM_TRANSPORT
        activeStreamListener?.disconnect()
      #endif
    }
  }
#endif
