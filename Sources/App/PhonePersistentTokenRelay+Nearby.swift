// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD && !REFINEID_STREAM_TRANSPORT
  import CardCore
  import Foundation
  import RappEngine

  /// The nearby relay's half of the phone relay, in a build without the
  /// stream: MultipeerConnectivity advertises nearby, and its one
  /// connection carries one session over the selected pairing.
  @MainActor
  extension PhonePersistentTokenRelay {
    /// Frames the nearby connection may deliver before its session starts.
    internal static let maximumPreCoordinatorFrames = 4

    /// How long the nearby relay pauses before it advertises again after
    /// its connection closed.
    internal static let nearbyRedialDelayMilliseconds = 150

    /// Advertises nearby, unless the relay already runs.
    internal func startNearby() {
      guard relay == nil, hasUsableSelectedPair() else { return }
      let connectionID = UUID()
      let nearby = PersistentRelaySession(
        role: .cardHolder,
        displayName: "RefineID iPhone"
      ) { [weak self] event in
        Task { @MainActor in
          self?.receiveNearby(event, connectionID: connectionID)
        }
      }
      nearbyConnectionID = connectionID
      relay = nearby
      nearby.start()
    }

    internal func hasUsableSelectedPair() -> Bool {
      (try? PhoneProxyPairSelection.resolveSelectedPair(vault: vault)) != nil
    }

    private func receiveNearby(_ event: PersistentRelayEvent, connectionID: UUID) {
      guard nearbyConnectionID == connectionID else { return }
      switch event {
      case .connected:
        openNearbySession()

      case .frame(let frame):
        if let session = session(on: .nearby) {
          session.receive(frame)
        } else if preCoordinatorFrames.count < Self.maximumPreCoordinatorFrames {
          preCoordinatorFrames.append(frame)
        } else {
          relay?.cancel()
        }

      case .closed:
        session(on: .nearby)?.transportClosed()
        relay = nil
        nearbyConnectionID = nil
        preCoordinatorFrames.removeAll(keepingCapacity: false)
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(Self.nearbyRedialDelayMilliseconds))
          self.start()
        }
      }
    }

    /// Opens the session the nearby connection carries.
    private func openNearbySession() {
      guard session(on: .nearby) == nil, let relay,
        let pair = try? PhoneProxyPairSelection.resolveSelectedPair(vault: vault)
      else {
        relay?.cancel()
        return
      }
      let frames = RappClosureFrameTransport(
        sender: { [weak relay] frame in
          guard let relay else { throw PersistentRelayTransportError.disconnected }
          try relay.send(frame)
        },
        closer: { [weak relay] in relay?.cancel() })
      let earlyFrames = preCoordinatorFrames
      preCoordinatorFrames.removeAll(keepingCapacity: false)
      let opened = openSession(
        pair: pair, on: .nearby, transportProfile: rappStreamProfileName(), frames: frames,
        earlyFrames: earlyFrames)
      if opened == nil { relay.cancel() }
    }
  }
#endif
