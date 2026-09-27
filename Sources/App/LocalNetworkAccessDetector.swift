// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import Foundation
  import Network
  import os

  /// Reads the local-network permission from a connection's own verdict.
  ///
  /// Browsing refusal is silent, but a direct connection to the LAN
  /// reports a state: reaching the router at all means access was
  /// granted, while the permission failure means it was denied. An
  /// undecided prompt leaves the connection waiting, which reads as
  /// neither and lets the flow proceed under watch instead of guessing.
  internal enum LocalNetworkAccessDetector {
    // MARK: Nested Types

    internal enum Access {
      case allowed
      case denied
    }

    private enum ProbeVerdict {
      case allowed
      case denied
      case undecided
    }

    /// Carries one probe connection across the cancellation boundary.
    private final class ConnectionBox: @unchecked Sendable {
      private let lock = NSLock()
      private var stored: NWConnection?

      var connection: NWConnection? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
      }
    }

    /// Settles one probe continuation exactly once across racing states.
    private final class ProbeSettlement: @unchecked Sendable {
      private let lock = NSLock()
      private var settled = false

      func finish(
        with verdict: ProbeVerdict,
        continuation: CheckedContinuation<ProbeVerdict, Never>
      ) {
        let first = lock.withLock { () -> Bool in
          guard !settled else { return false }
          settled = true
          return true
        }
        if first {
          continuation.resume(returning: verdict)
        }
      }
    }

    // MARK: Static Properties

    private static let wifiInterfaceName = "en0"
    private static let gatewayHostOffset: UInt32 = 1
    private static let fallbackGatewayLastOctet: UInt32 = 254
    private static let octetShift: UInt32 = 8
    /// One IPv4 octet's worth of bits, for splitting an address to print.
    private static let octetMask: UInt32 = 255
    private static let octetCount = 4
    private static let routerHTTPPort: UInt16 = 80
    private static let routerHTTPSPort: UInt16 = 443
    private static let routerDNSPort: UInt16 = 53
    private static let probePorts: [UInt16] = [routerHTTPPort, routerHTTPSPort, routerDNSPort]
    private static let quickVerdictSeconds: UInt64 = 5
    private static let denialWatchSeconds: UInt64 = 120

    /// Posted when the permission failure lands after the flow moved on.
    ///
    /// The observer must re-check that remote access is still on; the
    /// holder may have turned it off meanwhile.
    internal static let accessDeniedNotification = Notification.Name(
      "fi.refineid.localNetworkAccessDenied"
    )

    private static let logger = Logger(
      subsystem: "fi.refineid.ReFineID", category: "local-network-access")

    // MARK: Static Functions

    /// Answers whether this app may use the local network.
    ///
    /// Decided states answer fast from the probe. A still-waiting
    /// probe means the system prompt is up or the gateway is quiet;
    /// either way the caller proceeds and watches for the denial.
    internal static func currentAccess() async -> Access {
      guard lanProbeTarget() != nil else { return .allowed }
      if let quick = await raceProbes(deadlineSeconds: quickVerdictSeconds) {
        return quick == .denied ? .denied : .allowed
      }
      watchForDenial(windowSeconds: denialWatchSeconds)
      return .allowed
    }

    /// Watches for a late permission failure within the window.
    ///
    /// The watch ends on the first terminal probe verdict or when the
    /// window passes.
    internal static func watchForDenial(windowSeconds: UInt64) {
      Task.detached {
        guard lanProbeTarget() != nil else { return }
        if await raceProbes(deadlineSeconds: windowSeconds) == .denied {
          NotificationCenter.default.post(name: accessDeniedNotification, object: nil)
        }
      }
    }

    // MARK: Private Helpers

    /// The likeliest gateway address from the Wi-Fi interface, if any.
    ///
    /// The first address past the subnet base answers on all but the
    /// most exotic home gateways; exotic ones simply never answer and
    /// the flow proceeds under watch instead of blocking on them.
    private static func lanProbeTarget() -> String? {
      var interfaces: UnsafeMutablePointer<ifaddrs>?
      guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
      defer { freeifaddrs(first) }
      var cursor: UnsafeMutablePointer<ifaddrs>? = first
      while let current = cursor {
        defer { cursor = current.pointee.ifa_next }
        guard
          String(cString: current.pointee.ifa_name) == wifiInterfaceName,
          let address = current.pointee.ifa_addr,
          address.pointee.sa_family == UInt8(AF_INET),
          let mask = current.pointee.ifa_netmask
        else { continue }
        let own = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { socket in
          UInt32(bigEndian: socket.pointee.sin_addr.s_addr)
        }
        let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { socket in
          UInt32(bigEndian: socket.pointee.sin_addr.s_addr)
        }
        let base = own & netmask
        var candidate = base + gatewayHostOffset
        if candidate == own {
          candidate = base | fallbackGatewayLastOctet
        }
        guard candidate != own else { return nil }
        var octets: [String] = []
        var remaining = candidate
        for _ in 0..<octetCount {
          octets.append(String(remaining & octetMask))
          remaining >>= octetShift
        }
        return octets.reversed().joined(separator: ".")
      }
      return nil
    }

    /// Races one probe per port; nil when all still wait at the deadline.
    private static func raceProbes(deadlineSeconds: UInt64) async -> ProbeVerdict? {
      guard let router = lanProbeTarget() else { return nil }
      return await withTaskGroup(of: ProbeVerdict.self) { group in
        for port in probePorts {
          group.addTask { await probe(host: router, port: port) }
        }
        group.addTask {
          try? await Task.sleep(for: .seconds(deadlineSeconds))
          return .undecided
        }
        for await verdict in group {
          group.cancelAll()
          return verdict == .undecided ? nil : verdict
        }
        return nil
      }
    }

    /// Probes one router port until it answers or the race is cancelled.
    private static func probe(host: String, port: UInt16) async -> ProbeVerdict {
      let connectionBox = ConnectionBox()
      return await withTaskCancellationHandler(
        operation: {
          await withCheckedContinuation { continuation in
            let settled = ProbeSettlement()
            guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
              settled.finish(with: .allowed, continuation: continuation)
              return
            }
            let connection = NWConnection(
              host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
            connection.stateUpdateHandler = { state in
              handleProbeState(
                state,
                connection: connection,
                settled: settled,
                continuation: continuation)
            }
            connectionBox.connection = connection
            guard !Task.isCancelled else {
              connection.cancel()
              settled.finish(with: .allowed, continuation: continuation)
              return
            }
            connection.start(queue: .global(qos: .userInitiated))
          }
        },
        onCancel: {
          connectionBox.connection?.cancel()
        })
    }

    /// Settles one probe from a connection state change.
    private static func handleProbeState(
      _ state: NWConnection.State,
      connection: NWConnection,
      settled: ProbeSettlement,
      continuation: CheckedContinuation<ProbeVerdict, Never>
    ) {
      switch state {
      case .ready:
        logger.debug("local-network probe ready")
        connection.cancel()
        settled.finish(with: .allowed, continuation: continuation)
      case .failed(let error):
        logger.debug("local-network probe failed: \(String(describing: error))")
        connection.cancel()
        settled.finish(
          with: isPermissionError(error) ? .denied : .allowed,
          continuation: continuation)
      case .cancelled:
        settled.finish(with: .allowed, continuation: continuation)
      case .waiting, .preparing, .setup:
        break
      @unknown default:
        break
      }
    }

    /// Whether the failure is the permission gate rather than the network.
    private static func isPermissionError(_ error: NWError) -> Bool {
      let reported = error as NSError
      logger.debug(
        "local-network probe error domain \(reported.domain) code \(reported.code)")
      return reported.domain == NSPOSIXErrorDomain
        && reported.code == Int(EPERM)
    }

  }
#endif
