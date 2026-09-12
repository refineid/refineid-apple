// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(Network) && canImport(RappEngine)
  import Foundation
  import Network
  import RappEngine

  #if canImport(MultipeerConnectivity)
    @preconcurrency import MultipeerConnectivity
  #endif

  /// Discovers and publishes local peer identity announcements over mDNS/Bonjour and MultipeerConnectivity.
  ///
  /// Enables instantaneous zero-touch pairing across local Wi-Fi, Apple Wireless Direct Link (AWDL),
  /// and Bluetooth without requiring manual pairing codes or cloud synchronization delays.
  public final class RappLocalDiscovery: @unchecked Sendable {
    // MARK: Constants

    internal enum Constants {
      internal static let shortIDPrefixLength = 8
      internal static let publicKeyByteCount = 32
      internal static let lengthHeaderByteCount = 4
      internal static let maxPayloadByteCount = 65_536
    }

    /// The Bonjour service type for local device auto-pairing discovery.
    public static let serviceType = "_refineid-disc._tcp"

    // MARK: Properties

    internal let localIdentity: RappDeviceIdentity
    internal let localRole: RappDeviceRole
    /// The Bonjour service type used by this discovery instance.
    public let serviceType: String
    internal let onDiscovered: @Sendable (RappCloudDeviceRecord) -> Void
    internal let queue = DispatchQueue(label: "fi.refineid.local-discovery")
    private let onLiveDevicesChanged: (@Sendable (Set<UUID>, Set<String>) -> Void)?
    private var listener: NWListener?
    private var browser: NWBrowser?
    #if canImport(MultipeerConnectivity)
      private var multipeerHelper: MultipeerDiscoveryHelper?
    #endif
    private var isCancelled = false
    private var contactedEndpoints = Set<String>()

    // MARK: Initialization

    /// Creates a local discovery instance for advertising and discovering nearby peers.
    @preconcurrency
    public init(
      localIdentity: RappDeviceIdentity,
      localRole: RappDeviceRole,
      serviceType: String = RappLocalDiscovery.serviceType,
      onLiveDevicesChanged: (@Sendable (Set<UUID>, Set<String>) -> Void)? = nil,
      onDiscovered: @escaping @Sendable (RappCloudDeviceRecord) -> Void
    ) {
      self.localIdentity = localIdentity
      self.localRole = localRole
      self.serviceType = serviceType
      self.onLiveDevicesChanged = onLiveDevicesChanged
      self.onDiscovered = onDiscovered
    }

    // MARK: Lifecycle

    /// Starts advertising the local device and browsing for local peers.
    public func start() {
      queue.async {
        guard !self.isCancelled else { return }
        self.startAdvertising()
        self.startBrowsing()
        #if canImport(MultipeerConnectivity)
          let helper = MultipeerDiscoveryHelper(
            localIdentity: self.localIdentity,
            localRole: self.localRole,
            onDiscovered: self.onDiscovered
          )
          helper.start()
          self.multipeerHelper = helper
        #endif
      }
    }

    /// Stops advertising and browsing.
    public func cancel() {
      queue.async {
        self.isCancelled = true
        self.listener?.cancel()
        self.listener = nil
        self.browser?.cancel()
        self.browser = nil
        self.onLiveDevicesChanged?([], [])
        #if canImport(MultipeerConnectivity)
          self.multipeerHelper?.cancel()
          self.multipeerHelper = nil
        #endif
      }
    }

    // MARK: Advertising

    private func startAdvertising() {
      var txtRecord = NWTXTRecord()
      txtRecord["devid"] = localIdentity.deviceID.uuidString
      txtRecord["name"] = localIdentity.deviceName
      txtRecord["model"] = localIdentity.modelName
      txtRecord["role"] = localRole == .holder ? "holder" : "requester"
      txtRecord["pk"] = localIdentity.publicKeyData.base64EncodedString()

      let parameters = NWParameters.tcp
      parameters.includePeerToPeer = true

      guard let madeListener = try? NWListener(using: parameters) else { return }
      let shortID = String(localIdentity.deviceID.uuidString.prefix(Constants.shortIDPrefixLength))
      madeListener.service = NWListener.Service(
        name: "RefineID-\(shortID)",
        type: serviceType,
        domain: nil,
        txtRecord: txtRecord
      )
      madeListener.newConnectionHandler = { [weak self] connection in
        guard let self else {
          connection.cancel()
          return
        }
        handleIncomingDiscovery(connection)
      }
      madeListener.start(queue: queue)
      self.listener = madeListener
    }

    // MARK: Browsing

    private func startBrowsing() {
      let parameters = NWParameters.tcp
      parameters.includePeerToPeer = true

      let madeBrowser = NWBrowser(
        for: .bonjourWithTXTRecord(type: serviceType, domain: nil),
        using: parameters
      )

      madeBrowser.browseResultsChangedHandler = { [weak self] results, _ in
        guard let self else { return }
        var liveIDs = Set<UUID>()
        var liveNames = Set<String>()
        for result in results {
          if case .bonjour(let txt) = result.metadata {
            if let devIDString = txt["devid"], let devID = UUID(uuidString: devIDString) {
              liveIDs.insert(devID)
            }
            if let name = txt["name"] {
              liveNames.insert(name.lowercased())
            }
          }
          if case .service(let serviceName, _, _, _) = result.endpoint {
            liveNames.insert(serviceName.lowercased())
          }
          handleBrowseResult(result)
        }
        onLiveDevicesChanged?(liveIDs, liveNames)
      }

      madeBrowser.start(queue: queue)
      self.browser = madeBrowser
    }

    private func handleBrowseResult(_ result: NWBrowser.Result) {
      if case .bonjour(let txt) = result.metadata,
        let devIDString = txt["devid"],
        let devID = UUID(uuidString: devIDString),
        devID != localIdentity.deviceID,
        let name = txt["name"],
        let model = txt["model"],
        let roleString = txt["role"],
        let pkBase64 = txt["pk"],
        let pkData = Data(base64Encoded: pkBase64),
        pkData.count == Constants.publicKeyByteCount
      {
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
        onDiscovered(record)
        return
      }

      // If TXT record is unavailable or delayed by mDNS multicast snooping, connect directly over TCP
      guard case .service(let name, _, _, _) = result.endpoint,
        name.hasPrefix("RefineID-"),
        !name.contains(
          String(localIdentity.deviceID.uuidString.prefix(Constants.shortIDPrefixLength)))
      else { return }

      let endpointKey = "\(name)"
      guard contactedEndpoints.insert(endpointKey).inserted else { return }

      connectAndExchange(endpoint: result.endpoint)
    }
  }

#endif
