// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_TIMESTAMP_CONFIG

  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// Cancelled and dismissed probes record nothing and store nothing.
  ///
  /// Serialized: the tests share one isolated domain and take turns.
  @Suite(.serialized)
  @MainActor
  internal struct TimestampSettingsModelLifecycleTests {
    /// An isolated domain; the tests never touch the shared defaults.
    private static func freshDefaults() throws -> UserDefaults {
      let name = "TimestampSettingsModelLifecycleTests"
      let defaults = try #require(UserDefaults(suiteName: name))
      defaults.removePersistentDomain(forName: name)
      return defaults
    }

    /// A cancelled probe records nothing, not even a failure.
    @Test
    internal func cancelledProbeRecordsNothing() async throws {
      let defaults = try Self.freshDefaults()
      let model = TimestampSettingsModel(
        defaults: defaults,
        prober: { _ in throw URLError(.cancelled) },
        autoTestDelay: .seconds(30)
      )
      model.draft = "http://tsa.example.com/tsa"
      await model.runTest()
      #expect(
        TimestampAuthorityStore.verification(for: "http://tsa.example.com/tsa", in: defaults)
          == nil
      )
      #expect(
        TimestampAuthorityStore.load(from: defaults) == TimestampAuthorityStore.defaultAuthority
      )
      #expect(!model.testing)
    }

    /// A probe cancelled mid-flight never completes, even when released.
    @Test
    internal func cancelledTaskSkipsCompletion() async throws {
      let defaults = try Self.freshDefaults()
      let gate = TimestampSettingsProbeDoubles.ProbeGate()
      let model = TimestampSettingsModel(
        defaults: defaults,
        prober: { _ in await gate.suspend() },
        autoTestDelay: .seconds(30)
      )
      model.draft = "http://tsa.example.com/tsa"
      let cancelled = Task {
        await model.runTest()
      }
      var spins = 0
      while !gate.hasEntered {
        spins += 1
        try #require(spins < 200, "The probe never started.")
        try await Task.sleep(for: .milliseconds(5))
      }
      cancelled.cancel()
      gate.release()
      await cancelled.value
      #expect(
        TimestampAuthorityStore.verification(for: "http://tsa.example.com/tsa", in: defaults)
          == nil
      )
      #expect(!model.testing)
    }

    /// Dismissing the pane stops a scheduled probe and drops the draft.
    @Test
    internal func dismissPaneStopsAScheduledProbe() async throws {
      let defaults = try Self.freshDefaults()
      TimestampAuthorityStore.store("http://stored.example/tsa", in: defaults)
      let log = TimestampSettingsProbeDoubles.CallLog()
      let model = TimestampSettingsModel(
        defaults: defaults,
        prober: { target in await log.record(target) },
        autoTestDelay: .milliseconds(20)
      )
      model.draft = "http://typed.example/tsa"
      model.draftChanged()
      model.dismissPane()
      #expect(model.draft == "http://stored.example/tsa")
      try await Task.sleep(for: .milliseconds(300))
      let targets = await log.targets
      #expect(targets.isEmpty)
      #expect(
        TimestampAuthorityStore.verification(for: "http://typed.example/tsa", in: defaults) == nil
      )
    }

    /// Dismissing the pane mid-probe keeps no verdict for the draft.
    @Test
    internal func dismissPaneDuringAProbeKeepsNothing() async throws {
      let defaults = try Self.freshDefaults()
      TimestampAuthorityStore.store("http://stored.example/tsa", in: defaults)
      let gate = TimestampSettingsProbeDoubles.ProbeGate()
      let model = TimestampSettingsModel(
        defaults: defaults,
        prober: { _ in await gate.suspend() },
        autoTestDelay: .seconds(30)
      )
      model.draft = "http://typed.example/tsa"
      let dismissed = Task {
        await model.runTest()
      }
      var spins = 0
      while !gate.hasEntered {
        spins += 1
        try #require(spins < 200, "The probe never started.")
        try await Task.sleep(for: .milliseconds(5))
      }
      model.dismissPane()
      gate.release()
      await dismissed.value
      #expect(model.draft == "http://stored.example/tsa")
      #expect(
        TimestampAuthorityStore.verification(for: "http://typed.example/tsa", in: defaults) == nil
      )
      #expect(!model.testing)
    }

    /// Typing the shipped default clears any stored custom URL immediately.
    @Test
    internal func typingTheDefaultAuthorityClearsAStoredCustomUrl() async throws {
      let defaults = try Self.freshDefaults()
      TimestampAuthorityStore.store("http://stored.example/tsa", in: defaults)
      let log = TimestampSettingsProbeDoubles.CallLog()
      let model = TimestampSettingsModel(
        defaults: defaults,
        prober: { target in await log.record(target) },
        autoTestDelay: .milliseconds(20)
      )
      model.draft = TimestampAuthorityStore.defaultAuthority
      model.draftChanged()
      #expect(TimestampAuthorityStore.configured(in: defaults) == nil)
      #expect(
        TimestampAuthorityStore.load(from: defaults) == TimestampAuthorityStore.defaultAuthority
      )
      #expect(model.verification == nil)
      model.dismissPane()
      #expect(model.draft == TimestampAuthorityStore.defaultAuthority)
      let targets = await log.targets
      #expect(targets.isEmpty)
    }

    /// Typing the bare shipped address without http:// also clears a stored custom URL.
    @Test
    internal func typingTheBareDefaultAddressClearsAStoredCustomUrl() throws {
      let defaults = try Self.freshDefaults()
      TimestampAuthorityStore.store("http://stored.example/tsa", in: defaults)
      let model = TimestampSettingsModel(
        defaults: defaults,
        prober: { _ in try await Task.sleep(for: .milliseconds(1)) },
        autoTestDelay: .seconds(30)
      )
      model.draft = TimestampAuthorityStore.defaultAddress
      model.draftChanged()
      #expect(TimestampAuthorityStore.configured(in: defaults) == nil)
      #expect(
        TimestampAuthorityStore.load(from: defaults) == TimestampAuthorityStore.defaultAuthority
      )
    }
  }

#endif
