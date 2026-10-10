// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// What the phone's Remote Access screen says about serving the card.
internal enum HolderServingState: Equatable, Sendable {
  /// A paired computer holds a session now.
  case connected

  /// Serving stopped after a failure or the holder's own disconnect, and
  /// waits for the holder to resume it.
  case halted

  /// Waiting for a paired computer.
  case listening

  /// Remote Access is off.
  case off

  /// Remote Access is on, but nothing is paired.
  case unpaired

  // MARK: Static Functions

  /// The state for these facts; the first rule that matches wins.
  internal static func derive(
    enabled: Bool,
    paired: Bool,
    halted: Bool,
    connected: Bool
  ) -> Self {
    guard enabled else { return .off }
    guard paired else { return .unpaired }
    if connected {
      return .connected
    }
    return halted ? .halted : .listening
  }
}
