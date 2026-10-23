// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import dnssd
  import Network

  /// Learns whether macOS lets this app use the local network, once remote
  /// use is on.
  ///
  /// The first Bonjour browse is what asks macOS for the permission
  /// (CC-96), so nothing browses while remote use is off. A browse waiting
  /// on `kDNSServiceErr_PolicyDenied` has no local-network access (Apple
  /// TN3179, "Understanding local network privacy"): that blocks remote use
  /// for as long as it lasts. The browse reads no record and ends once it
  /// is allowed.
  @MainActor
  internal final class LocalNetworkPermissionWatch: RemoteUseWatch {
    /// What a browser's state says about the permission.
    internal enum Permission: Equatable, Sendable {
      /// The browse runs: the app may use the local network.
      case allowed

      /// The browse waits on the privacy policy.
      case refused
    }

    // MARK: Properties

    private var browser: NWBrowser?
    private var report: (@MainActor (RemoteUseBlockage?) -> Void)?

    // MARK: Computed Properties

    internal var isWatching: Bool {
      browser != nil
    }

    // MARK: Static Functions

    /// What a browser in `state` says about the permission; nil when it
    /// says nothing about it.
    nonisolated internal static func permission(in state: NWBrowser.State) -> Permission? {
      switch state {
      case .ready:
        .allowed

      case .waiting(let error), .failed(let error):
        refusesPermission(error) ? .refused : nil

      case .setup, .cancelled:
        nil

      @unknown default:
        nil
      }
    }

    /// Whether `error` is the local network privacy refusal.
    nonisolated private static func refusesPermission(_ error: NWError) -> Bool {
      guard case .dns(let code) = error else { return false }
      return Int(code) == kDNSServiceErr_PolicyDenied
    }

    // MARK: Functions

    internal func start(report: @escaping @MainActor (RemoteUseBlockage?) -> Void) {
      guard browser == nil else { return }
      self.report = report
      let made = NWBrowser(
        for: .bonjour(type: StreamRelayListener.serviceType, domain: nil), using: .tcp)
      made.stateUpdateHandler = { [weak self] state in
        // The browser calls back on the main queue it was started on.
        MainActor.assumeIsolated {
          self?.receive(state)
        }
      }
      browser = made
      made.start(queue: .main)
    }

    internal func stop() {
      browser?.stateUpdateHandler = nil
      browser?.cancel()
      browser = nil
      report = nil
    }

    private func receive(_ state: NWBrowser.State) {
      switch Self.permission(in: state) {
      case .allowed:
        report?(nil)
        // The browse has done its work.
        browser?.stateUpdateHandler = nil
        browser?.cancel()
        browser = nil

      case .refused:
        report?(.localNetworkNotAllowed)

      case nil:
        break
      }
    }
  }

#endif
