// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation
  import Observation

  /// Whether browser requests to the paired phone are paused, as the
  /// token extension last recorded.
  ///
  /// The extension announces each pause it begins or ends; the app reads
  /// the record then and wakes once when the pause runs out.
  /// Called by CoreFoundation on its own thread when the token extension
  /// begins or ends a pause; hops to the main actor for the read.
  private func remoteCardPauseDidChange(
    _: CFNotificationCenter?,
    _: UnsafeMutableRawPointer?,
    _: CFNotificationName?,
    _: UnsafeRawPointer?,
    _: CFDictionary?
  ) {
    Task { @MainActor in RemoteCardPause.shared.changed() }
  }

  @MainActor
  @Observable
  internal final class RemoteCardPause {
    // MARK: Static Properties

    internal static let shared = RemoteCardPause()

    /// Milliseconds before a second read after a change, for a write the
    /// other process has not yet made visible here.
    private static let settleMilliseconds: Int64 = 500

    /// Milliseconds added to a pause's end before reading it again.
    private static let wakeMarginMilliseconds: Int64 = 100

    // MARK: Properties

    /// When the current pause ends, or `nil` when requests reach the phone.
    internal private(set) var pausedUntil: Date?

    @ObservationIgnored private var expiry: Task<Void, Never>?

    // MARK: Lifecycle

    private init() {
      CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        nil,
        remoteCardPauseDidChange,
        RemoteSignCoolDown.changeNotificationName as CFString,
        nil,
        .deliverImmediately
      )
      refresh()
    }

    // MARK: Functions

    /// Reads the record now and once more shortly after.
    internal func changed() {
      refresh()
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .milliseconds(Self.settleMilliseconds))
        self?.refresh()
      }
    }

    /// Lets the next request reach the phone.
    internal func resume() {
      RemoteSignCoolDown.shared.resume()
      refresh()
    }

    /// Reads the record and wakes again when the pause runs out.
    internal func refresh() {
      expiry?.cancel()
      expiry = nil
      let until = RemoteSignCoolDown.shared.pausedUntil(at: Date())
      pausedUntil = until
      guard let until else { return }
      let delay = max(until.timeIntervalSinceNow, 0)
      expiry = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(delay) + .milliseconds(Self.wakeMarginMilliseconds))
        guard !Task.isCancelled else { return }
        self?.refresh()
      }
    }
  }

#endif
