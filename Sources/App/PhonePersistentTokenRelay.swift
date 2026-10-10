// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation
  import Network
  import RappEngine
  /// Owns the phone side of one mutually authenticated RAPP connection.
  ///
  /// The transport is an opaque frame carrier chosen by the selected pair:
  /// MultipeerConnectivity advertises nearby, while the stream profile dials
  /// the requester's stored listener endpoints. All identity, sequencing,
  /// operation, and fail-stop decisions belong to RAPP.
  #if DEBUG
    /// The event's case name alone, which is what a timeline needs.
    private func eventCaseName(_ event: RappConnectionCoordinator.Event) -> String {
      String(describing: event).prefix { $0 != "(" }.description
    }
  #endif

  @MainActor
  internal final class PhonePersistentTokenRelay: ObservableObject {
    // MARK: Nested Types

    internal enum RelistenPolicy {
      case automatic
      case explicitUserActionRequired
    }

    // MARK: Static Properties

    internal static let shared = PhonePersistentTokenRelay()

    internal static let maximumPreCoordinatorFrames = 4
    internal static let recentContactWindowSeconds: TimeInterval = 180
    /// How long the stream transport pauses before re-listening after a
    /// connection closes.
    internal static let streamRedialDelayMilliseconds = 100
    internal static let nearbyRedialDelayMilliseconds = 150

    // MARK: Properties

    internal let vault = RappDeviceVault()
    private let policy = RappRequesterPolicy.interactive
    private var pairingsObserver: (any NSObjectProtocol)?
    internal var relay: PersistentRelaySession?
    #if REFINEID_STREAM_TRANSPORT
      internal var streamListeners: [String: StreamRelayListener] = [:]
      internal var streamDialers: [String: StreamRelaySession] = [:]
      internal var streamContexts: [String: PhoneStreamPairContext] = [:]
      internal var activeStreamListener: StreamRelayListener?
      internal var activeStreamDialer: StreamRelaySession?
      internal var sessionListening = SessionListening()
    #endif
    internal var coordinator: RappConnectionCoordinator?
    #if REFINEID_SLIM_RELAY
      internal var slimSession: SignRelaySession?
      internal var slimProxy: SignRelayProxy?
    #endif
    internal var dispatcher: RappPhoneProxyDispatcher?
    internal var connectionID: UUID?
    internal var preCoordinatorFrames: [Data] = []
    internal var relistenPolicy = RelistenPolicy.automatic
    @Published internal var isActivelyConnected = false
    @Published internal var lastPeerContactDate: Date?
    @Published internal var isPeerOnline = false

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
          self?.updatePeerOnlineState()
          self?.start()
        }
      }
    }

    // MARK: Functions

    internal func start() {
      updatePeerOnlineState()
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
          relistenPolicy == .automatic,
          hasUsablePair()
        else { return }
        let contexts = PhoneStreamPairContext.resolveAll(vault: vault)
        guard !contexts.isEmpty else { return }
        pruneStreamTransports(keeping: streamKeys(for: contexts))
        startListening(contexts)
      #else
        guard relay == nil, coordinator == nil,
          relistenPolicy == .automatic,
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
        lastPeerContactDate = Date()
        establish(connectionID: connectionID)

      case .frame(let frame):
        lastPeerContactDate = Date()
        #if REFINEID_SLIM_RELAY
          if slimSession != nil {
            deliverInOrder { [weak self] in
              // The delivery may outlive the connection it belongs to;
              // a frame for a gone connection must not touch the next
              // one's session.
              guard let self, await self.connectionID == connectionID else { return }
              await receiveSlim(frame)
            }
            return
          }
        #endif
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
        transport: transport,
        failTransport: failTransport
      )
    }

    internal func establishCoordinator(
      connectionID: UUID,
      pair explicitPair: RappPairRecord?,
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
          relistenPolicy = .explicitUserActionRequired
          failTransport()
          return
        }
        #if REFINEID_SLIM_RELAY
          try establishSlim(pair: pair, transport: transport)
        #else
          let made = try RappConnectionCoordinator(
            role: .proxy,
            pair: pair,
            vault: vault,
            transport: transport,
            maximumLifetimeMilliseconds:
              policy.maximumOperationLifetimeMilliseconds,
            liveness: policy.liveness
          )
          let madeDispatcher = RappPhoneProxyDispatcher(
            inbox: RappAuthorizationInbox.shared
          ) { [weak self] in
            self?.requireExplicitUserAction()
          }
          coordinator = made
          dispatcher = madeDispatcher
          lastPeerContactDate = Date()
          isActivelyConnected = true

          let earlyFrames = preCoordinatorFrames
          preCoordinatorFrames.removeAll(keepingCapacity: false)
          pumpEvents(
            from: made,
            dispatcher: madeDispatcher,
            connectionID: connectionID,
            earlyFrames: earlyFrames
          )
        #endif
      } catch {
        relistenPolicy = .explicitUserActionRequired
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

    private func observe(
      _ event: RappConnectionCoordinator.Event,
      connectionID: UUID
    ) {
      guard self.connectionID == connectionID else { return }
      #if DEBUG
        HolderTrace.say("session event \(eventCaseName(event))")
      #endif
      if PhoneRelayFailStops.requireExplicitUserAction(event) {
        relistenPolicy = .explicitUserActionRequired
      }
    }

    private func requireExplicitUserAction() {
      relistenPolicy = .explicitUserActionRequired
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
