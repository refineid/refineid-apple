// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_SCS
  import CardCore
  import Foundation
  import Network
  import Security

  /// Builds the loopback TLS parameters for `ScsServer` from the
  /// stored server leaf and offline root CA chain.
  internal enum ScsTlsConfiguration {
    internal static func makeLocalParameters(
      onStatusFailure: @Sendable (String?) -> Void
    ) -> NWParameters? {
      guard let chain = ScsIdentityStore.obtain(),
        let secIdentity = sec_identity_create_with_certificates(
          chain.identity, [chain.rootCertificate] as CFArray),
        let port = NWEndpoint.Port(rawValue: ScsDispatcher.port)
      else {
        ScsLog.error("server: TLS identity chain unavailable; SCS not started")
        onStatusFailure(
          String(localized: "Could not prepare the localhost TLS certificate in Keychain."))
        return nil
      }
      let tls = NWProtocolTLS.Options()
      sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
      let parameters = NWParameters(tls: tls)
      parameters.allowLocalEndpointReuse = false
      parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
        host: NWEndpoint.Host("127.0.0.1"), port: port)
      return parameters
    }
  }

  extension ScsServer {
    internal convenience init(onStatusFailure: @escaping @Sendable (String?) -> Void) {
      let cardBackend = ScsCardBackend()
      self.init(
        limits: .standard,
        backend: cardBackend,
        cardCancellationHook: { token, work in cardBackend.withCancellation(token, work) },
        resetBackendHook: { cardBackend.resetSessionState() },
        makeParameters: {
          ScsTlsConfiguration.makeLocalParameters(onStatusFailure: onStatusFailure)
        },
        observeState: { _ in
          // Production state transitions report through ScsLog.
        },
        onStatusFailure: onStatusFailure
      )
    }
  }
#endif
