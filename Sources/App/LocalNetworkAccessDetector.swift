// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import CardCore
  import Foundation
  import Network
  import os

  /// Reads the local-network permission from Bonjour self-discovery.
  ///
  /// Denial is silent at the state level: browsing and advertising
  /// both report ready and never raise the permission failure. What
  /// denial stops is the announcements themselves, so the probe
  /// advertises an instance and browses for it: the first sighting
  /// proves access, while a window that stays dark reads as denied.
  /// Without Wi-Fi there is no permission question to answer, so the
  /// flow proceeds and pairing reports its own outcome.
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

    /// Carries one probe's cancel across the cancellation boundary.
    private final class CancelBox: @unchecked Sendable {
      private let lock = NSLock()
      private var stored: (() -> Void)?

      func set(_ cancel: @escaping () -> Void) {
        lock.withLock { stored = cancel }
      }

      func take() -> (() -> Void)? {
        lock.withLock {
          let cancel = stored
          stored = nil
          return cancel
        }
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

    /// The probe advertises under its own name on the discovery type.
    private static let probeServiceName = "RefineID-Probe"
    private static let ownServiceNamePrefix = "RefineID-"
    private static let probeTXTKey = "probe"
    private static let probeTXTValue = "1"
    private static let wifiInterfaceName = "en0"
    private static let quickVerdictSeconds: UInt64 = 10

    private static let logger = Logger(
      subsystem: "fi.refineid.ReFineID", category: "local-network-access")

    // MARK: Static Functions

    /// Answers whether this app may use the local network.
    ///
    /// The first sighting settles the answer early; only a window
    /// that stays fully dark reads as denied.
    internal static func currentAccess() async -> Access {
      guard hasWiFiInterface() else {
        logger.info("local-network probe has no Wi-Fi, assuming allowed")
        return .allowed
      }
      let verdict = await raceProbes(deadlineSeconds: quickVerdictSeconds)
      let access: Access = verdict == .allowed ? .allowed : .denied
      logger.info(
        "local-network access reads \(access == .allowed ? "allowed" : "denied", privacy: .public)"
      )
      return access
    }

    // MARK: Private Helpers

    /// Whether the Wi-Fi interface holds an IPv4 address.
    private static func hasWiFiInterface() -> Bool {
      var interfaces: UnsafeMutablePointer<ifaddrs>?
      guard getifaddrs(&interfaces) == 0, let first = interfaces else { return false }
      defer { freeifaddrs(first) }
      var cursor: UnsafeMutablePointer<ifaddrs>? = first
      while let current = cursor {
        defer { cursor = current.pointee.ifa_next }
        guard
          String(cString: current.pointee.ifa_name) == wifiInterfaceName,
          let address = current.pointee.ifa_addr,
          address.pointee.sa_family == UInt8(AF_INET)
        else { continue }
        return true
      }
      return false
    }

    /// Races browsing against the window; nil when nothing arrived.
    private static func raceProbes(deadlineSeconds: UInt64) async -> ProbeVerdict? {
      await withTaskGroup(of: ProbeVerdict.self) { group in
        group.addTask { await probeBrowsing() }
        group.addTask { await advertiseForWindow(seconds: deadlineSeconds) }
        for await verdict in group {
          group.cancelAll()
          return verdict == .undecided ? nil : verdict
        }
        return nil
      }
    }

    /// Advertises the probe instance for the window, then yields.
    ///
    /// The advertisement guarantees a discoverable instance on quiet
    /// networks; its own states carry no verdict.
    private static func advertiseForWindow(seconds: UInt64) async -> ProbeVerdict {
      guard let listener = makeProbeListener() else {
        logger.info("local-network advertise probe has no listener")
        try? await Task.sleep(for: .seconds(seconds))
        return .undecided
      }
      listener.stateUpdateHandler = { state in
        logger.info("local-network advertise probe \(String(describing: state))")
      }
      listener.start(queue: .global(qos: .userInitiated))
      defer { listener.cancel() }
      try? await Task.sleep(for: .seconds(seconds))
      return .undecided
    }

    /// Browses the discovery type until a sighting or the race ends.
    private static func probeBrowsing() async -> ProbeVerdict {
      let cancelBox = CancelBox()
      return await withTaskCancellationHandler(
        operation: {
          await withCheckedContinuation { continuation in
            let settled = ProbeSettlement()
            let settle: @Sendable (ProbeVerdict) -> Void = { verdict in
              cancelBox.take()?()
              settled.finish(with: verdict, continuation: continuation)
            }
            let browser = NWBrowser(
              for: .bonjour(type: RappLocalDiscovery.serviceType, domain: nil),
              using: .tcp
            )
            browser.stateUpdateHandler = { state in
              handleBrowserState(state, settle: settle)
            }
            browser.browseResultsChangedHandler = { results, _ in
              logResultComposition(results)
              if !results.isEmpty {
                settle(.allowed)
              }
            }
            cancelBox.set { browser.cancel() }
            guard !Task.isCancelled else {
              settle(.allowed)
              return
            }
            browser.start(queue: .global(qos: .userInitiated))
          }
        },
        onCancel: {
          cancelBox.take()?()
        })
    }

    /// Logs what the browse probe sees without naming foreign peers.
    private static func logResultComposition(_ results: Set<NWBrowser.Result>) {
      var probeCount = 0
      var ownCount = 0
      var otherCount = 0
      for result in results {
        guard case .service(let name, _, _, _) = result.endpoint else {
          otherCount += 1
          continue
        }
        if name.hasPrefix(probeServiceName) {
          probeCount += 1
        } else if name.hasPrefix(ownServiceNamePrefix) {
          ownCount += 1
        } else {
          otherCount += 1
        }
      }
      let composition = "probe \(probeCount) own \(ownCount) other \(otherCount)"
      logger.info(
        "local-network browse sees \(results.count, privacy: .public) \(composition, privacy: .public)"
      )
    }

    /// Builds the probe advertiser on the discovery type.
    private static func makeProbeListener() -> NWListener? {
      guard let listener = try? NWListener(using: .tcp) else { return nil }
      var txtRecord = NWTXTRecord()
      txtRecord[probeTXTKey] = probeTXTValue
      listener.service = NWListener.Service(
        name: probeServiceName,
        type: RappLocalDiscovery.serviceType,
        domain: nil,
        txtRecord: txtRecord
      )
      listener.newConnectionHandler = { connection in
        connection.cancel()
      }
      return listener
    }

    /// Settles the browse probe from a browser state change.
    private static func handleBrowserState(
      _ state: NWBrowser.State,
      settle: @Sendable (ProbeVerdict) -> Void
    ) {
      switch state {
      case .ready:
        logger.info("local-network browse probe ready")
      case .failed(let error):
        logger.info("local-network browse probe failed: \(String(describing: error))")
        settle(isPermissionError(error) ? .denied : .allowed)
      case .cancelled:
        settle(.allowed)
      case .waiting(let error):
        if isPermissionError(error) {
          logger.info("local-network browse probe waiting on permission, reading denied")
          settle(.denied)
        }
      case .setup:
        break
      @unknown default:
        break
      }
    }

    /// Whether the failure is the permission gate rather than the network.
    private static func isPermissionError(_ error: NWError) -> Bool {
      if case .posix(let code) = error {
        logger.info("local-network probe posix code \(code.rawValue, privacy: .public)")
        return code.rawValue == EPERM
      }
      let reported = error as NSError
      logger.info(
        "local-network probe error domain \(reported.domain, privacy: .public) code \(reported.code, privacy: .public)"
      )
      return reported.domain == NSPOSIXErrorDomain
        && reported.code == Int(EPERM)
    }

  }
#endif
