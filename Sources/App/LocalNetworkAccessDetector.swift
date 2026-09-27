// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import CardCore
  import Foundation
  import Network
  import os

  /// Reads the local-network permission from the Bonjour gate itself.
  ///
  /// Browsing and advertising ride the gated path, so a short-lived
  /// browser and advertiser report what the permission decides: ready
  /// means access was granted, while the permission failure means it
  /// was denied. An undecided prompt leaves both waiting, which reads
  /// as neither and lets the flow proceed under watch instead of
  /// guessing.
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
    private static let probeTXTKey = "probe"
    private static let probeTXTValue = "1"
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
    /// probe means the system prompt is up; either way the caller
    /// proceeds and watches for the denial.
    internal static func currentAccess() async -> Access {
      if let quick = await raceProbes(deadlineSeconds: quickVerdictSeconds) {
        let access: Access = quick == .denied ? .denied : .allowed
        logger.info(
          "local-network access reads \(access == .allowed ? "allowed" : "denied", privacy: .public)"
        )
        return access
      }
      watchForDenial(windowSeconds: denialWatchSeconds)
      logger.info("local-network access undecided, proceeding under watch")
      return .allowed
    }

    /// Watches for a late permission failure within the window.
    ///
    /// The watch ends on the first terminal probe verdict or when the
    /// window passes.
    internal static func watchForDenial(windowSeconds: UInt64) {
      Task.detached {
        if await raceProbes(deadlineSeconds: windowSeconds) == .denied {
          NotificationCenter.default.post(name: accessDeniedNotification, object: nil)
        }
      }
    }

    // MARK: Private Helpers

    /// Races browsing against advertising; nil when both still wait.
    private static func raceProbes(deadlineSeconds: UInt64) async -> ProbeVerdict? {
      await withTaskGroup(of: ProbeVerdict.self) { group in
        group.addTask { await probeBrowsing() }
        group.addTask { await probeAdvertising() }
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

    /// Browses the discovery type until the gate answers or cancels.
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
              logger.info(
                "local-network browse probe sees \(results.count, privacy: .public) results")
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

    /// Advertises a probe instance until the gate answers or cancels.
    private static func probeAdvertising() async -> ProbeVerdict {
      let cancelBox = CancelBox()
      return await withTaskCancellationHandler(
        operation: {
          await withCheckedContinuation { continuation in
            let settled = ProbeSettlement()
            let settle: @Sendable (ProbeVerdict) -> Void = { verdict in
              cancelBox.take()?()
              settled.finish(with: verdict, continuation: continuation)
            }
            guard let listener = makeProbeListener() else {
              logger.info("local-network advertise probe has no listener")
              settle(.allowed)
              return
            }
            listener.stateUpdateHandler = { state in
              handleListenerState(state, settle: settle)
            }
            cancelBox.set { listener.cancel() }
            guard !Task.isCancelled else {
              settle(.allowed)
              return
            }
            listener.start(queue: .global(qos: .userInitiated))
          }
        },
        onCancel: {
          cancelBox.take()?()
        })
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
        settle(.allowed)
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

    /// Settles the advertise probe from a listener state change.
    private static func handleListenerState(
      _ state: NWListener.State,
      settle: @Sendable (ProbeVerdict) -> Void
    ) {
      switch state {
      case .ready:
        logger.info("local-network advertise probe ready")
        settle(.allowed)
      case .failed(let error):
        logger.info("local-network advertise probe failed: \(String(describing: error))")
        settle(isPermissionError(error) ? .denied : .allowed)
      case .cancelled:
        settle(.allowed)
      case .waiting(let error):
        if isPermissionError(error) {
          logger.info("local-network advertise probe waiting on permission, reading denied")
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
