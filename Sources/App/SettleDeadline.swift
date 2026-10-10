// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Reports when a state has lasted past a limit.
///
/// A card mints its identity in well under a second; one that stays
/// without an identity much longer is worth a warning, and only then.
@MainActor
internal final class SettleDeadline {
  // MARK: Properties

  internal private(set) var hasExpired = false

  private let limit: Duration
  private let onChange: @MainActor (Bool) -> Void
  private var pending: Task<Void, Never>?

  // MARK: Lifecycle

  internal init(limit: Duration, onChange: @escaping @MainActor (Bool) -> Void) {
    self.limit = limit
    self.onChange = onChange
  }

  // MARK: Functions

  /// Records whether a card is present without an identity now.
  internal func cardWithoutIdentity(_ waiting: Bool) {
    pending?.cancel()
    pending = nil
    guard waiting else {
      set(false)
      return
    }
    let delay = limit
    pending = Task { @MainActor [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      self?.set(true)
    }
  }

  private func set(_ expired: Bool) {
    guard hasExpired != expired else { return }
    hasExpired = expired
    onChange(expired)
  }
}
