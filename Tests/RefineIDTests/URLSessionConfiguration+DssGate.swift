// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import Foundation

  /// The replacement `DssGateSessionHook` exchanges in.
  extension URLSessionConfiguration {
    /// The original ephemeral configuration with the gate's protocol first.
    ///
    /// Once exchanged, calling this name runs the original. Activation relies
    /// on `DssGateSessionHook.isFixtureActive` (`@TaskLocal`), which propagates
    /// into structured child tasks (including `SigningNetwork.firstAnswer`'s
    /// `withThrowingTaskGroup`) and leaves unrelated detached tasks native.
    /// `SigningNetwork.validatedSessionConfiguration(validating:)` is the sole
    /// production caller of `URLSessionConfiguration.ephemeral`.
    @objc
    internal dynamic class func dssGateEphemeral() -> URLSessionConfiguration {
      let configuration = Self.dssGateEphemeral()
      if DssGateSessionHook.isFixtureActive {
        configuration.protocolClasses =
          [DssGateUrlProtocol.self] + (configuration.protocolClasses ?? [])
      }
      return configuration
    }
  }

#endif
