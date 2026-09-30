// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) || os(macOS)
  import CardCore

  /// Single-purpose container for entered PIN2 digits during holder authorization.
  ///
  /// Deliberately not `CustomStringConvertible`, not `CustomDebugStringConvertible`,
  /// and custom reflection produces an empty mirror to prevent PIN leakage into logs
  /// or error strings (AGENTS.md Rule #2).
  internal struct Pin2AuthorizationDigits: Sendable, Equatable, CustomReflectable {
    internal let digits: String

    internal var customMirror: Mirror {
      Mirror(self, children: [:])
    }

    internal init?(digits: String) {
      guard Pin2(digits: digits) != nil else { return nil }
      self.digits = digits
    }
  }
#endif
