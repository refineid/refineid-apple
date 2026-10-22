// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One connection a session listener accepted, from its arrival until it
/// closes.
public struct StreamSessionConnection: Hashable, Sendable {
  /// Names this connection apart from every other the listener accepted.
  private let identifier = UUID()

  /// A connection never named before.
  internal init() {
    // The identifier is drawn fresh.
  }
}
