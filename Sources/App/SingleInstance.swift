// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit

  /// Makes this launch the only running copy of the app.
  ///
  /// macOS keeps an app single-instance per bundle path, not per
  /// identity: a build-products copy and /Applications can run side
  /// by side, each with its own idea of the card. One card cannot
  /// serve two masters - an instance holding the card session is why
  /// a Safari login once hung - and two versions on screen means the
  /// one being tested may be the stale one.
  ///
  /// The newest launch wins. Whoever is already running is asked to
  /// quit and given a moment to comply, so the copy just installed
  /// or just built is the copy that runs; an instance too stuck to
  /// quit is exactly the instance that must not keep the card, and
  /// is made to.
  ///
  /// A development launch with a virtual card holds no card session, so it
  /// runs beside the copy that may, and leaves it running.
  internal enum SingleInstance {
    /// How long the incumbent gets to quit on its own.
    private static let quitGraceSeconds: TimeInterval = 2

    /// How often the incumbent is looked in on while it quits.
    private static let pollSeconds: TimeInterval = 0.05

    /// Asks every other running copy to quit, then continues launch.
    internal static func enforce() {
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(DemoMode.launchArgument) { return }
      #endif
      guard let identity = Bundle.main.bundleIdentifier else { return }
      let mine = ProcessInfo.processInfo.processIdentifier
      let incumbents =
        NSRunningApplication
        .runningApplications(
          withBundleIdentifier: identity
        )
        .filter { $0.processIdentifier != mine }
      guard !incumbents.isEmpty else { return }
      for incumbent in incumbents {
        incumbent.terminate()
      }
      // NSRunningApplication only observes the other process while
      // the run loop turns, so the wait spins it rather than sleeps.
      let deadline = Date(timeIntervalSinceNow: Self.quitGraceSeconds)
      while Date() < deadline,
        incumbents.contains(where: { !$0.isTerminated })
      {
        RunLoop.current.run(
          mode: .default,
          before: Date(timeIntervalSinceNow: Self.pollSeconds)
        )
      }
      for incumbent in incumbents where !incumbent.isTerminated {
        incumbent.forceTerminate()
      }
    }
  }

#endif
