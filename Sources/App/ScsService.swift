// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  import SwiftUI

  /// Starts the local signing server only for the holder's stored opt-in.
  @MainActor
  internal final class ScsService: ObservableObject {
    internal static let shared = ScsService()

    /// Where the holder's opt-in is stored; off by default.
    internal static let enabledKey = "fi.refineid.scs.enabled"

    @Published internal private(set) var isEnabled: Bool
    private var isRunning = false
    private let defaults: UserDefaults
    private let start: () -> Void
    private let stop: () -> Void

    private convenience init() {
      let server = ScsServer()
      self.init(defaults: .standard, start: { server.start() }, stop: { server.stop() })
    }

    internal init(defaults: UserDefaults, start: @escaping () -> Void, stop: @escaping () -> Void) {
      self.defaults = defaults
      self.start = start
      self.stop = stop
      isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    /// Restores an explicit opt-in without creating an identity when disabled.
    internal func restore() {
      guard isEnabled, !isRunning else { return }
      isRunning = true
      start()
    }

    internal func setEnabled(_ enabled: Bool) {
      guard enabled != isEnabled else { return }
      defaults.set(enabled, forKey: Self.enabledKey)
      isEnabled = enabled
      if enabled {
        restore()
      } else {
        isRunning = false
        stop()
      }
    }
  }
#endif
