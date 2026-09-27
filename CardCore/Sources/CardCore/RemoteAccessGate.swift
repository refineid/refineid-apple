// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Whether this device may serve or seek a card over the local network.
///
/// Remote card use is opt-in: nothing advertises, browses, or asks for
/// notification permission until the holder turns Remote Access on. The
/// choice persists on the device, and a fresh install starts off. macOS
/// keeps its established requester behavior and always reads on.
public enum RemoteAccessGate: Sendable {
  // MARK: Nested Types

  private enum SessionChoice {
    case disabled
    case enabled
    case unset
  }

  // MARK: Static Properties

  /// The defaults key the holder's choice persists under.
  public static let enabledDefaultsKey = "fi.refineid.rapp.remote-serving-enabled"

  /// The launch argument that forces remote access on for one run.
  public static let enabledLaunchArgument = "--remote-access-on"

  private static let lock = NSLock()

  /// The in-memory choice for this run, when a test set one.
  nonisolated(unsafe) private static var sessionChoice = SessionChoice.unset

  // MARK: Public API

  /// Whether remote transports may start on this launch.
  public static var isEnabled: Bool {
    #if os(macOS)
      return true
    #else
      return effectiveEnabled()
    #endif
  }

  /// Records the holder's choice.
  ///
  /// Test runs keep the choice in memory so one test cannot leak it
  /// into the next through persisted defaults. Production macOS has
  /// no choice to record and ignores the call.
  public static func setEnabled(_ enabled: Bool) {
    if TestCredentialEnvironment.isTestMode {
      setSessionOverride(enabled)
      return
    }
    #if os(macOS)
      return
    #else
      setStoredEnabled(enabled, in: .standard)
    #endif
  }

  // MARK: Internal Helpers

  /// The gated answer, factored so tests on any host can drive it.
  internal static func effectiveEnabled() -> Bool {
    switch lockedSessionChoice() {
    case .enabled:
      return true
    case .disabled:
      return false
    case .unset:
      break
    }
    if TestCredentialEnvironment.isTestMode {
      return ProcessInfo.processInfo.arguments.contains(enabledLaunchArgument)
    }
    return storedEnabled(in: .standard)
  }

  /// The persisted choice, off when nothing was ever stored.
  internal static func storedEnabled(in store: UserDefaults) -> Bool {
    store.bool(forKey: enabledDefaultsKey)
  }

  /// Persists the holder's choice.
  internal static func setStoredEnabled(_ enabled: Bool, in store: UserDefaults) {
    store.set(enabled, forKey: enabledDefaultsKey)
  }

  /// Records the in-memory choice for this run.
  internal static func setSessionOverride(_ enabled: Bool) {
    lock.withLock { sessionChoice = enabled ? .enabled : .disabled }
  }

  /// Clears the in-memory choice for this run.
  internal static func clearSessionOverride() {
    lock.withLock { sessionChoice = .unset }
  }

  private static func lockedSessionChoice() -> SessionChoice {
    lock.withLock { sessionChoice }
  }
}
