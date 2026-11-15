// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_TIMESTAMP_CONFIG

  import Foundation
  import SwiftUI

  /// The Time Stamp pane's draft: typed, tested, stored only when valid.
  ///
  /// The field edits a draft that is never stored as typed. A probe -
  /// automatic after a pause, or the Test button - validates it: a
  /// verified token stores it, anything else leaves the previous
  /// address configured. Closing the pane with an unproven draft
  /// reverts to that address.
  @MainActor
  internal final class TimestampSettingsModel: ObservableObject {
    /// Pause after the last keystroke before the draft is probed, in seconds.
    private static let autoTestDelaySeconds = 1

    /// The address being edited; stored only after a passed probe.
    @Published internal var draft: String

    /// Whether a probe is running.
    @Published internal private(set) var testing = false

    /// The verdict for the draft's address, when the last probe ran
    /// against exactly it.
    @Published internal private(set) var verification: TimestampAuthorityStore.Verification?

    /// Where the address and verdicts live.
    private let defaults: UserDefaults

    /// One timestamp exchange, live or stubbed.
    private let prober: @Sendable (String) async throws -> Void

    /// Pause after the last keystroke before the draft is probed.
    private let autoTestDelay: Duration

    /// The scheduled or running probe, if any.
    private var testTask: Task<Void, Never>?

    /// The latest probe; older completions are discarded.
    private var generation = 0

    /// A model over the shared defaults and the live authority.
    internal init() {
      self.defaults = .standard
      self.prober = { try await TimestampClient.probe($0) }
      self.autoTestDelay = .seconds(Self.autoTestDelaySeconds)
      self.draft = Self.initialDraft(in: .standard)
    }

    /// A model over `defaults`, probing with `prober`.
    internal init(
      defaults: UserDefaults,
      prober: @escaping @Sendable (String) async throws -> Void,
      autoTestDelay: Duration
    ) {
      self.defaults = defaults
      self.prober = prober
      self.autoTestDelay = autoTestDelay
      self.draft = Self.initialDraft(in: defaults)
    }

    /// The field's opening address: the stored one with its scheme,
    /// else the shipped authority.
    private static func initialDraft(in defaults: UserDefaults) -> String {
      if let configured = TimestampAuthorityStore.configured(in: defaults),
        let resolved = TimestampAuthorityStore.resolvedRequestAddress(configured)
      {
        return resolved
      }
      return TimestampAuthorityStore.defaultAuthority
    }

    /// The draft changed: trim it, show any verdict for it, then
    /// probe it after a pause.
    internal func draftChanged() {
      testTask?.cancel()
      testTask = nil
      testing = false
      let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed != draft {
        draft = trimmed
        return
      }
      guard let target = TimestampAuthorityStore.resolvedRequestAddress(draft) else {
        verification = nil
        return
      }
      verification = TimestampAuthorityStore.verification(for: target, in: defaults)
      testTask = Task {
        do {
          try await Task.sleep(for: autoTestDelay)
        } catch {
          return
        }
        await runTest()
      }
    }

    /// Drop the draft: the pane shows the stored address again.
    ///
    /// The settings scene keeps this model across window closes, so
    /// reopening would otherwise show an unproven draft as if it
    /// were configured.
    internal func revertToStored() {
      draft = Self.initialDraft(in: defaults)
    }

    /// Forget the configured address; the shipped service answers again.
    internal func restoreDefaults() {
      testTask?.cancel()
      testTask = nil
      TimestampAuthorityStore.restoreDefaults(in: defaults)
      draft = TimestampAuthorityStore.defaultAuthority
      draftChanged()
    }

    /// One probe of the draft's address, kept only if still current.
    internal func runTest() async {
      guard let target = TimestampAuthorityStore.resolvedRequestAddress(draft) else {
        return
      }
      generation += 1
      let current = generation
      testing = true
      defer {
        if generation == current {
          testing = false
        }
      }
      let failure: TimestampClient.Failure?
      do {
        try await prober(target)
        failure = nil
      } catch is CancellationError {
        return
      } catch let caught as TimestampClient.Failure {
        failure = caught
      } catch {
        failure = TimestampClient.probeFailure(from: error)
      }
      complete(target: target, failure: failure, current: current)
    }

    /// Keep a finished probe: record it when still current, store
    /// the draft when it proved valid.
    private func complete(
      target: String,
      failure: TimestampClient.Failure?,
      current: Int
    ) {
      guard
        generation == current,
        TimestampAuthorityStore.resolvedRequestAddress(draft) == target
      else {
        return
      }
      TimestampAuthorityStore.recordVerification(
        address: target,
        failure: failure,
        date: Date(),
        in: defaults
      )
      if failure == nil {
        TimestampAuthorityStore.store(draft, in: defaults)
      }
      verification = TimestampAuthorityStore.verification(for: target, in: defaults)
    }

  }

#endif
