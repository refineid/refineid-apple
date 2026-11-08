// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import Foundation

  /// The replacement `DssGateSessionHook` exchanges in.
  extension URLSessionConfiguration {
    /// The original ephemeral configuration with the gate's protocol first.
    ///
    /// Once exchanged, calling this name runs the original.
    @objc
    internal dynamic class func dssGateEphemeral() -> URLSessionConfiguration {
      let configuration = Self.dssGateEphemeral()
      configuration.protocolClasses =
        [DssGateUrlProtocol.self] + (configuration.protocolClasses ?? [])
      return configuration
    }
  }

#endif
