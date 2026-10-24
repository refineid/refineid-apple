// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(Network)
  import dnssd
  import Foundation
  import Network

  /// Asks the platform whether this app may reach the addresses a published
  /// service resolves to.
  ///
  /// A dial to a service endpoint does not report a local-network denial:
  /// its own path stays satisfied and only the paths to the addresses
  /// beneath it are refused, so the dial itself only times out. The probe
  /// resolves the service and its host and opens a UDP connection to each
  /// address. Such a connection carries the verdict on its own path as soon
  /// as it starts, and sends nothing.
  ///
  /// All work runs on the caller's serial queue; `cancel()` runs on it too
  /// and stops every callback.
  internal final class LocalNetworkProbe: @unchecked Sendable {
    // MARK: Static Properties

    private static let noFlags: DNSServiceFlags = 0
    private static let bothAddressFamilies = DNSServiceProtocol(
      kDNSServiceProtocol_IPv4 | kDNSServiceProtocol_IPv6)
    private static let anyInterface = UInt32(kDNSServiceInterfaceIndexAny)
    /// What `getnameinfo` returns on success.
    private static let nameInfoSucceeded: Int32 = 0

    // MARK: Properties

    private let service: NWEndpoint
    private let queue: DispatchQueue
    private let onVerdict: @Sendable (LocalNetworkVerdict) -> Void
    private var serviceResolution: DNSServiceRef?
    private var addressLookup: DNSServiceRef?
    private var servicePort: NWEndpoint.Port?
    private var connections: [NWConnection] = []
    private var isDone = false

    // MARK: Lifecycle

    /// A probe for `service` that reports its one verdict on `queue`.
    internal init(
      service: NWEndpoint,
      queue: DispatchQueue,
      onVerdict: @escaping @Sendable (LocalNetworkVerdict) -> Void
    ) {
      self.service = service
      self.queue = queue
      self.onVerdict = onVerdict
    }

    // MARK: Static Functions

    /// The numeric host of a socket address, scoped to its interface when
    /// it is link-local.
    private static func numericHost(_ address: UnsafePointer<sockaddr>) -> NWEndpoint.Host? {
      var text = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      let status = getnameinfo(
        address, socklen_t(address.pointee.sa_len), &text, socklen_t(text.count), nil, 0,
        NI_NUMERICHOST)
      guard status == nameInfoSucceeded else { return nil }
      let bytes = text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
      guard let numeric = String(bytes: bytes, encoding: .utf8) else { return nil }
      return NWEndpoint.Host(numeric)
    }

    // MARK: Functions

    /// Starts resolving the service; any other endpoint gets no verdict.
    internal func start() {
      guard case .service(let name, let type, let domain, let interface) = service else {
        return
      }
      let interfaceIndex = interface.map { UInt32($0.index) } ?? Self.anyInterface
      var reference: DNSServiceRef?
      let error = DNSServiceResolve(
        &reference, Self.noFlags, interfaceIndex, name, type, domain,
        { _, _, interfaceIndex, error, _, hostTarget, port, _, _, context in
          guard let context else { return }
          let probe = Unmanaged<LocalNetworkProbe>.fromOpaque(context).takeUnretainedValue()
          probe.resolved(
            error: error, hostTarget: hostTarget, networkOrderPort: port,
            interfaceIndex: interfaceIndex)
        },
        Unmanaged.passUnretained(self).toOpaque())
      serviceResolution = attach(reference, error: error)
    }

    /// Stops every lookup and connection; no verdict follows.
    internal func cancel() {
      isDone = true
      for reference in [serviceResolution, addressLookup].compactMap(\.self) {
        DNSServiceRefDeallocate(reference)
      }
      serviceResolution = nil
      addressLookup = nil
      for connection in connections {
        connection.stateUpdateHandler = nil
        connection.cancel()
      }
      connections = []
    }

    /// Puts a started lookup on the queue; nil, after reporting what its
    /// error says, when it did not start.
    private func attach(_ reference: DNSServiceRef?, error: DNSServiceErrorType) -> DNSServiceRef? {
      guard error == kDNSServiceErr_NoError, let reference else {
        if let reference {
          DNSServiceRefDeallocate(reference)
        }
        report(LocalNetworkVerdict.of(resolutionError: error))
        return nil
      }
      guard DNSServiceSetDispatchQueue(reference, queue) == kDNSServiceErr_NoError else {
        DNSServiceRefDeallocate(reference)
        return nil
      }
      return reference
    }

    /// Looks up the addresses of the host the service resolved to.
    private func resolved(
      error: DNSServiceErrorType,
      hostTarget: UnsafePointer<CChar>?,
      networkOrderPort: UInt16,
      interfaceIndex: UInt32
    ) {
      guard !isDone, addressLookup == nil else { return }
      guard error == kDNSServiceErr_NoError, let hostTarget,
        let port = NWEndpoint.Port(rawValue: UInt16(bigEndian: networkOrderPort))
      else {
        report(LocalNetworkVerdict.of(resolutionError: error))
        return
      }
      servicePort = port
      var reference: DNSServiceRef?
      let started = DNSServiceGetAddrInfo(
        &reference, Self.noFlags, interfaceIndex, Self.bothAddressFamilies, hostTarget,
        { _, _, _, error, _, address, _, context in
          guard let context else { return }
          let probe = Unmanaged<LocalNetworkProbe>.fromOpaque(context).takeUnretainedValue()
          probe.found(error: error, address: address)
        },
        Unmanaged.passUnretained(self).toOpaque())
      addressLookup = attach(reference, error: started)
    }

    /// Opens a connection to one address the host resolved to.
    private func found(error: DNSServiceErrorType, address: UnsafePointer<sockaddr>?) {
      guard !isDone else { return }
      guard error == kDNSServiceErr_NoError, let address, let port = servicePort,
        let host = Self.numericHost(address)
      else {
        report(LocalNetworkVerdict.of(resolutionError: error))
        return
      }
      let connection = NWConnection(host: host, port: port, using: .udp)
      connection.stateUpdateHandler = { [weak self, weak connection] state in
        guard let self, let connection else { return }
        report(
          LocalNetworkVerdict.of(
            state: state, unsatisfiedReason: connection.currentPath?.unsatisfiedReason))
      }
      connections.append(connection)
      connection.start(queue: queue)
    }

    /// Reports the first verdict and ends the probe.
    private func report(_ verdict: LocalNetworkVerdict?) {
      guard !isDone, let verdict else { return }
      cancel()
      onVerdict(verdict)
    }
  }
#endif
