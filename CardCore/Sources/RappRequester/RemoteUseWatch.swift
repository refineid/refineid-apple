// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// One of the watches that run while remote use is on: starting it is what
/// asks the platform for the permission it covers (CC-96), and it reports
/// what blocks remote use on its side.
///
/// The switch takes any two of these, so a test drives the decision core
/// without a Bluetooth manager or a browse.
@preconcurrency
@MainActor
public protocol RemoteUseWatch: AnyObject {
  /// Whether the watch is running.
  var isWatching: Bool { get }

  /// Starts watching; `report` takes each blockage found, and nil when it
  /// clears.
  func start(report: @escaping @MainActor (RemoteUseBlockage?) -> Void)

  /// Stops watching and lets go of everything the watch holds.
  func stop()
}
