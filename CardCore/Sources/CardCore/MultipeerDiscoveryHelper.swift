// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(MultipeerConnectivity) && canImport(RappEngine)
  import Foundation
  @preconcurrency import MultipeerConnectivity
  import RappEngine

  /// Helper discovering and publishing peer identity announcements over MultipeerConnectivity.
  internal final class MultipeerDiscoveryHelper: NSObject, @unchecked Sendable,
    MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate
  {
    private enum Constants {
      static let publicKeyByteCount = 32
    }

    private static let serviceType = "refineid-disc"
    private let localPeer: MCPeerID
    private let discoveryInfo: [String: String]
    private let onDiscovered: (@Sendable (RappCloudDeviceRecord) -> Void)?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private let localDeviceID: UUID

    internal convenience init(
      localIdentity: RappDeviceIdentity,
      localRole: RappDeviceRole
    ) {
      self.init(localIdentity: localIdentity, localRole: localRole, onDiscovered: nil)
    }

    internal init(
      localIdentity: RappDeviceIdentity,
      localRole: RappDeviceRole,
      onDiscovered: (@Sendable (RappCloudDeviceRecord) -> Void)?
    ) {
      self.localDeviceID = localIdentity.deviceID
      let rolePrefix = localRole == .holder ? "card" : "host"
      self.localPeer = MCPeerID(displayName: "\(rolePrefix).\(localIdentity.deviceName)")
      self.discoveryInfo = [
        "devid": localIdentity.deviceID.uuidString,
        "name": localIdentity.deviceName,
        "model": localIdentity.modelName,
        "role": localRole == .holder ? "holder" : "requester",
        "pk": localIdentity.publicKeyData.base64EncodedString(),
      ]
      self.onDiscovered = onDiscovered
      super.init()
    }

    internal func start() {
      let adv = MCNearbyServiceAdvertiser(
        peer: localPeer,
        discoveryInfo: discoveryInfo,
        serviceType: Self.serviceType
      )
      adv.delegate = self
      adv.startAdvertisingPeer()
      self.advertiser = adv

      let brow = MCNearbyServiceBrowser(
        peer: localPeer,
        serviceType: Self.serviceType
      )
      brow.delegate = self
      brow.startBrowsingForPeers()
      self.browser = brow
    }

    internal func cancel() {
      advertiser?.stopAdvertisingPeer()
      advertiser?.delegate = nil
      advertiser = nil
      browser?.stopBrowsingForPeers()
      browser?.delegate = nil
      browser = nil
    }

    // MARK: MCNearbyServiceAdvertiserDelegate

    internal func advertiser(
      _ advertiser: MCNearbyServiceAdvertiser,
      didReceiveInvitationFromPeer peerID: MCPeerID,
      withContext context: Data?,
      invitationHandler: (Bool, MCSession?) -> Void
    ) {
      _ = (advertiser, peerID, context)
      // Discovery only; RAPP stream handles data transport
      invitationHandler(false, nil)
    }

    internal func advertiser(
      _ advertiser: MCNearbyServiceAdvertiser,
      didNotStartAdvertisingPeer error: any Error
    ) {
      _ = (advertiser, error)
      // Advertising start failure handled silently
    }

    // MARK: MCNearbyServiceBrowserDelegate

    // swiftlint:disable discouraged_optional_collection
    internal func browser(
      _ browser: MCNearbyServiceBrowser,
      foundPeer peerID: MCPeerID,
      withDiscoveryInfo info: [String: String]?
    ) {
      _ = (browser, peerID)
      guard let info,
        let devIDString = info["devid"],
        let devID = UUID(uuidString: devIDString),
        devID != localDeviceID,
        let name = info["name"],
        let model = info["model"],
        let roleString = info["role"],
        let pkBase64 = info["pk"],
        let pkData = Data(base64Encoded: pkBase64),
        pkData.count == Constants.publicKeyByteCount
      else { return }

      let role: RappDeviceRole = (roleString == "holder") ? .holder : .requester
      let record = RappCloudDeviceRecord(
        deviceID: devID,
        deviceName: name,
        modelName: model,
        role: role,
        staticPublicKey: pkData,
        rendezvousToken: RappSameAccountPairBuilder.deriveRendezvousToken(
          publicKeyA: pkData,
          publicKeyB: pkData
        ),
        updatedAt: Date()
      )
      onDiscovered?(record)
    }

    // swiftlint:enable discouraged_optional_collection

    internal func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
      _ = (browser, peerID)
      // Peer loss tracked via heartbeat / RAPP presence
    }

    internal func browser(
      _ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error
    ) {
      _ = (browser, error)
      // Browsing start failure handled silently
    }
  }
#endif
