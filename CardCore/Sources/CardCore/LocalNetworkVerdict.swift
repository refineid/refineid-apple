// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(Network)
  import dnssd
  import Network

  /// What one connection or name lookup says about this app's permission
  /// to use the local network.
  public enum LocalNetworkVerdict: Sendable, Equatable {
    /// The connection is ready: the app may reach the address.
    case allowed

    /// The platform refuses this app the local network.
    case denied

    // MARK: Static Functions

    /// The verdict of a connection in `state` whose current path is
    /// unsatisfied for `unsatisfiedReason`; nil while it says nothing.
    ///
    /// The denial is carried by the path to a numeric address (Apple
    /// TN3179, "Understanding local network privacy"). A path to a service
    /// or a host name stays satisfied while every address beneath it is
    /// refused, so only a connection to an address gives a verdict.
    public static func of(
      state: NWConnection.State,
      unsatisfiedReason: NWPath.UnsatisfiedReason?
    ) -> Self? {
      switch state {
      case .ready:
        .allowed

      case .preparing, .waiting, .failed:
        unsatisfiedReason == .localNetworkDenied ? .denied : nil

      case .setup, .cancelled:
        nil

      @unknown default:
        nil
      }
    }

    /// The verdict of a name lookup that ended with `error`; nil when the
    /// error is not the privacy refusal, `kDNSServiceErr_PolicyDenied`
    /// (TN3179).
    public static func of(resolutionError error: DNSServiceErrorType) -> Self? {
      Int(error) == kDNSServiceErr_PolicyDenied ? .denied : nil
    }

    /// The verdict of `connection` in the state it is in now.
    public static func of(_ connection: NWConnection) -> Self? {
      of(state: connection.state, unsatisfiedReason: connection.currentPath?.unsatisfiedReason)
    }

    /// The verdict of `connection` in `state`, which reports `error`: by
    /// its own path, or by its name lookup.
    public static func of(
      _ connection: NWConnection, in state: NWConnection.State, error: NWError
    ) -> Self? {
      of(state: state, unsatisfiedReason: connection.currentPath?.unsatisfiedReason)
        ?? of(connectionError: error)
    }

    /// The verdict of a connection that reports `error`.
    public static func of(connectionError error: NWError) -> Self? {
      guard case .dns(let code) = error else { return nil }
      return of(resolutionError: code)
    }
  }
#endif
