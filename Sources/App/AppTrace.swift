// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG
  import CardCore
#endif

/// The app's half of the shared extension trace.
///
/// The app drives a card directly on two paths the extensions never
/// touch - the Core NFC priming field and the status/diagnostic reads -
/// and those exchanges belong in the same buffer as the extension's, or
/// a priming failure and a mint failure cannot be read against each
/// other.
///
/// The same rule as ``TokenLog``: Debug and Profile only. TestFlight and
/// Release define no `DEBUG`, so the call compiles to nothing and the
/// `@autoclosure` line is never built. That matters here more than it
/// reads - this is called once per APDU, and ``CardExchangeTrace/line``
/// would otherwise format a string for every exchange of a shipped
/// login before discarding it.
internal enum AppTrace {
  /// Appends one complete Debug trace line to the shared trace.
  internal static func append(_ line: @autoclosure () -> String) {
    #if DEBUG
      ExtensionTrace.append(line())
    #endif
  }
}
