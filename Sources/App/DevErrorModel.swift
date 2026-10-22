// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG
  import Foundation
  import notify
  import Observation

  /// What the development error display shows, and how much of it.
  ///
  /// The log is read again whenever any RefineID process reports, and when
  /// the app comes to the front. An error newer than any seen before
  /// expands the display and runs ``onArrival``; the display collapses on
  /// its own after ``defaultCollapseDelay`` without one.
  @MainActor
  @Observable
  internal final class DevErrorModel {
    // MARK: Static Properties

    /// Seconds the display stays expanded after the newest error.
    nonisolated internal static let collapseDelaySeconds = 8

    /// How long the display stays expanded after the newest error.
    nonisolated internal static let defaultCollapseDelay: Duration = .seconds(collapseDelaySeconds)

    /// The one model every window shows.
    internal static let shared = DevErrorModel(collapseDelay: defaultCollapseDelay)

    /// The launch argument a screenshot or demonstration run passes to
    /// hide development aids.
    nonisolated internal static let hiddenArgument = "--hide-diagnostics"

    /// Whether this launch shows the display at all.
    nonisolated internal static let isEnabled =
      DevErrorLog.isRecording && !ProcessInfo.processInfo.arguments.contains(hiddenArgument)

    // MARK: Properties

    /// Every recent error, newest first.
    internal private(set) var entries: [DevErrorLog.Entry] = []

    /// Whether the display shows the newest error rather than only the
    /// count.
    internal private(set) var isExpanded = false

    /// Whether the full list is open.
    internal var isListShown = false

    /// Runs once for every error newer than any seen before.
    @ObservationIgnored internal var onArrival: (@MainActor () -> Void)?

    @ObservationIgnored private let collapseDelay: Duration
    @ObservationIgnored private var newestSeen: UUID?
    @ObservationIgnored private var collapseTimer: Task<Void, Never>?
    @ObservationIgnored private var isObserving = false

    // MARK: Computed Properties

    /// Every error as plain text, one per line and oldest first, as a log
    /// reads.
    internal var transcript: String {
      DevErrorLog.transcript(of: entries.reversed(), timeZone: .current)
    }

    // MARK: Lifecycle

    /// A model whose display collapses `collapseDelay` after the newest
    /// error.
    internal init(collapseDelay: Duration) {
      self.collapseDelay = collapseDelay
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
        collapse()
        return
      }
      guard newest.identifier != newestSeen else { return }
      newestSeen = newest.identifier
      isExpanded = true
      collapseTimer?.cancel()
      let delay = collapseDelay
      collapseTimer = Task { @MainActor [weak self] in
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return }
        self?.isExpanded = false
      }
      onArrival?()
    }

    /// Shows only the count until the next error.
    internal func collapse() {
      collapseTimer?.cancel()
      collapseTimer = nil
      isExpanded = false
    }

    /// Forgets every error, for every process, and closes the list.
    internal func clear() {
      DevErrorLog.clear()
      isListShown = false
      take([])
    }
  }
#endif
