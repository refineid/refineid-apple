// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import Foundation
  import ObjectiveC

  /// Puts `DssGateUrlProtocol` first in every ephemeral configuration.
  ///
  /// The signing network builds a fresh ephemeral configuration for
  /// each exchange, so this reaches it without changing the signing
  /// code. It holds while installed, between two `toggle` calls.
  internal enum DssGateSessionHook {
    /// Exchanges `+ephemeralSessionConfiguration` with the hooked one;
    /// a second call restores it.
    internal static func toggle() {
      guard
        let original = class_getClassMethod(
          URLSessionConfiguration.self,
          #selector(getter: URLSessionConfiguration.ephemeral)
        ),
        let hooked = class_getClassMethod(
          URLSessionConfiguration.self,
          #selector(URLSessionConfiguration.dssGateEphemeral)
        )
      else { return }
      method_exchangeImplementations(original, hooked)
    }
  }

#endif
