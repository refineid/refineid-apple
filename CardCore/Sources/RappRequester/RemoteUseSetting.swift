// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The holder's remote-use choice, as the switch reads and records it.
///
/// The switch takes any of these, so a test keeps the choice to itself
/// instead of writing the one the device persists.
public protocol RemoteUseSetting: AnyObject {
  /// Whether the holder's choice is on.
  var isEnabled: Bool { get }

  /// Records the holder's choice.
  func setEnabled(_ enabled: Bool)
}
