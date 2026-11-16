// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Persisted holder opt-in state machine for the localhost Signature
/// Creation Service.
///
/// Restoring an enabled opt-in starts the listener once; turning the
/// opt-in off stops the listener and removes the localhost TLS identity
/// and user trust settings so disabled installs retain neither key nor
/// certificate trust.
@preconcurrency
@MainActor
public final class ScsOptInController {
  /// The `UserDefaults` key storing the holder's opt-in; false when
  /// absent.
  public static let enabledKey = "fi.refineid.scs.enabled"

  /// Whether the holder has turned the signing service on.
  public private(set) var isEnabled: Bool

  private var isRunning = false
  private let defaults: UserDefaults
  private let start: () -> Void
  private let stop: () -> Void
  private let removeIdentity: () -> Void

  /// Creates an opt-in controller backed by `defaults`.
  public init(
    defaults: UserDefaults,
    start: @escaping () -> Void,
    stop: @escaping () -> Void,
    removeIdentity: @escaping () -> Void
  ) {
    self.defaults = defaults
    self.start = start
    self.stop = stop
    self.removeIdentity = removeIdentity
    self.isEnabled = defaults.bool(forKey: Self.enabledKey)
  }

  /// Starts the server if and only if the holder previously opted in.
  public func restore() {
    guard isEnabled, !isRunning else { return }
    isRunning = true
    start()
  }

  /// Updates the persisted opt-in, starting on opt-in and stopping plus
  /// removing the localhost identity and trust on opt-out.
  public func setEnabled(_ enabled: Bool) {
    guard enabled != isEnabled else { return }
    defaults.set(enabled, forKey: Self.enabledKey)
    isEnabled = enabled
    if enabled {
      restore()
    } else {
      isRunning = false
      stop()
      removeIdentity()
    }
  }
}
