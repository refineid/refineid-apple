// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  /// One of the watches that run while remote use is on: starting it is
  /// what asks macOS for the permission it covers (CC-96), and it reports
  /// what blocks remote use on its side.
  @MainActor
  internal protocol RemoteUseWatch: AnyObject {
    /// Whether the watch is running.
    var isWatching: Bool { get }

    /// Starts watching; `report` takes each blockage found, and nil when
    /// it clears.
    func start(report: @escaping @MainActor (RemoteUseBlockage?) -> Void)

    /// Stops watching and lets go of everything the watch holds.
    func stop()
  }

#endif
