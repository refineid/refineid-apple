// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_SCS
  import OSLog

  /// Diagnostic and operational logging for the localhost SCS.
  ///
  /// Never logs a PIN, PIN length, card serial, document body, or
  /// signature value. Ordinary flow logs in development builds only;
  /// listener, port-conflict, and identity errors log in every build so
  /// a squatted port or failed TLS startup is never silent.
  internal enum ScsLog {
    private static let logger = Logger(subsystem: "fi.refineid.ReFineID", category: "scs")

    /// Records ordinary control flow in development builds.
    internal static func info(_ message: @autoclosure () -> String) {
      #if DEBUG
        let text = message()
        Self.logger.info("\(text, privacy: .public)")
      #endif
    }

    /// Records an operational or security failure in all builds.
    internal static func error(_ message: @autoclosure () -> String) {
      let text = message()
      Self.logger.error("\(text, privacy: .public)")
    }
  }
#endif
