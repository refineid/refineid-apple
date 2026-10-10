// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Whether to show a session as connected.
///
/// A requester opens a session per operation, so a session ends and the
/// next begins moments apart. The indicator turns on at once and turns off
/// only after the session has stayed closed for `hold`.
@MainActor
internal final class ConnectionIndicator {
  // MARK: Static Properties

  /// Milliseconds a closed session still shows as connected.
  private static let defaultHoldMilliseconds: Int64 = 1_500

  /// How long a closed session still shows as connected.
  internal static let defaultHold: Duration = .milliseconds(defaultHoldMilliseconds)

  // MARK: Properties

  internal private(set) var isShown = false

  private let hold: Duration
  private let onChange: @MainActor (Bool) -> Void
  private var pendingOff: Task<Void, Never>?

  // MARK: Lifecycle

  internal init(hold: Duration, onChange: @escaping @MainActor (Bool) -> Void) {
    self.hold = hold
    self.onChange = onChange
  }

  // MARK: Functions

  /// Records whether a session is open now.
  internal func update(active: Bool) {
    pendingOff?.cancel()
    pendingOff = nil
    if active {
      set(true)
      return
    }
    guard isShown else { return }
    let delay = hold
    pendingOff = Task { @MainActor [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      self?.set(false)
    }
  }

  private func set(_ shown: Bool) {
    guard isShown != shown else { return }
    isShown = shown
    onChange(shown)
  }
}
