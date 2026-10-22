// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG
  import Foundation
  import notify
  import Observation

  /// What the development error strip shows, and when.
  ///
  /// A newer error than any shown brings the strip up; it fades on its own
  /// after ``defaultFadeDelay`` without one. The log is read again whenever
  /// any RefineID process reports, and when the app comes to the front.
  @MainActor
  @Observable
  internal final class DevErrorStripModel {
    // MARK: Static Properties

    /// How many errors the strip lists.
    nonisolated internal static let stripLineCount = 3

    /// Seconds the strip stays after the newest error.
    nonisolated internal static let fadeDelaySeconds = 8

    /// How long the strip stays after the newest error.
    nonisolated internal static let defaultFadeDelay: Duration = .seconds(fadeDelaySeconds)

    /// The one model the app's window shows.
    internal static let shared = DevErrorStripModel(fadeDelay: defaultFadeDelay)

    /// The launch argument a screenshot or demonstration run passes to
    /// hide development aids.
    nonisolated internal static let hiddenArgument = "--hide-diagnostics"

    /// Whether this launch shows the strip at all.
    nonisolated internal static let isEnabled =
      DevErrorLog.isRecording && !ProcessInfo.processInfo.arguments.contains(hiddenArgument)

    // MARK: Properties

    /// Every recent error, newest first.
    internal private(set) var entries: [DevErrorLog.Entry] = []

    /// Whether the strip is up.
    internal private(set) var isStripShown = false

    /// Whether the full list is open.
    internal var isListShown = false

    @ObservationIgnored private let fadeDelay: Duration
    @ObservationIgnored private var newestShown: UUID?
    @ObservationIgnored private var fade: Task<Void, Never>?
    @ObservationIgnored private var isObserving = false

    // MARK: Computed Properties

    /// The errors the strip lists, newest first.
    internal var stripEntries: ArraySlice<DevErrorLog.Entry> {
      entries.prefix(Self.stripLineCount)
    }

    // MARK: Lifecycle

    /// A model whose strip fades `fadeDelay` after the newest error.
    internal init(fadeDelay: Duration) {
      self.fadeDelay = fadeDelay
    }

    // MARK: Functions

    /// Starts following the log, once per process.
    internal func start() {
      guard Self.isEnabled, !isObserving else { return }
      isObserving = true
      var registration: Int32 = 0
      notify_register_dispatch(DevErrorLog.changedNotification, &registration, .main) {
        [weak self] _ in
        MainActor.assumeIsolated {
          self?.reload()
        }
      }
      reload()
    }

    /// Reads the log again.
    internal func reload() {
      guard Self.isEnabled else { return }
      take(DevErrorLog.read())
    }

    /// Takes the log as stored, oldest first.
    internal func take(_ stored: [DevErrorLog.Entry]) {
      entries = stored.reversed()
      guard let newest = stored.last else {
        hideStrip()
        return
      }
      guard newest.identifier != newestShown else { return }
      newestShown = newest.identifier
      isStripShown = true
      fade?.cancel()
      let delay = fadeDelay
      fade = Task { @MainActor [weak self] in
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return }
        self?.isStripShown = false
      }
    }

    /// Forgets every error, for every process, and closes the list.
    internal func clear() {
      DevErrorLog.clear()
      isListShown = false
      take([])
    }

    private func hideStrip() {
      fade?.cancel()
      fade = nil
      isStripShown = false
    }
  }
#endif
