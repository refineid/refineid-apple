// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Sweeps the stored pairings for idle expiry while the app runs (RAPP
/// v26.10.29 §4.6 item 5): at least once a day, besides the sweep at launch.
@MainActor
internal final class PairingIdleSweep {
  private static let secondsPerHour: Int64 = 3_600

  /// How long the app waits between sweeps; well under the day the
  /// specification allows, so a pairing expires within the hour it is due.
  internal static let interval = Duration.seconds(secondsPerHour)

  private var task: Task<Void, Never>?

  /// Runs `sweep` once each ``interval`` from now on; a sweep already
  /// running is kept.
  internal func start(_ sweep: @escaping @MainActor () -> Void) {
    guard task == nil else { return }
    task = Task { @MainActor in
      while !Task.isCancelled {
        try? await Task.sleep(for: Self.interval)
        guard !Task.isCancelled else { return }
        sweep()
      }
    }
  }
}
