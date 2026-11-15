// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_TIMESTAMP_CONFIG

  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// The settings draft is stored only after a passed probe.
  ///
  /// Serialized: the tests share one isolated domain and take turns.
  @Suite(.serialized)
  @MainActor
  internal struct TimestampSettingsModelTests {
    /// An isolated domain; the tests never touch the shared defaults.
    private static func freshDefaults() throws -> UserDefaults {
      let name = "TimestampSettingsModelTests"
      let defaults = try #require(UserDefaults(suiteName: name))
      defaults.removePersistentDomain(forName: name)
      return defaults
    }

    /// The logged targets once a probe lands, else whatever logged
    /// within five seconds.
    private static func awaitTargets(_ log: TimestampSettingsProbeDoubles.CallLog) async -> [String]
    {
      let deadline = ContinuousClock.now + .seconds(5)
      while ContinuousClock.now < deadline {
        let targets = await log.targets
        if !targets.isEmpty {
          return targets
        }
        try? await Task.sleep(for: .milliseconds(10))
      }
      return await log.targets
    }

    /// The field opens on the stored draft, else the shipped address.
    @Test
    internal func opensOnTheStoredDraft() throws {
      let defaults = try Self.freshDefaults()
      let fresh = TimestampSettingsModel(
        defaults: defaults,
        prober: { _ in try await Task.sleep(for: .milliseconds(1)) },
        autoTestDelay: .seconds(30)
      )
      #expect(fresh.draft == TimestampAuthorityStore.defaultAuthority)
      TimestampAuthorityStore.store("http://tsa.example.com/tsa", in: defaults)
      let reopened = TimestampSettingsModel(
        defaults: defaults,
        prober: { _ in try await Task.sleep(for: .milliseconds(1)) },
        autoTestDelay: .seconds(30)
      )
      #expect(reopened.draft == "http://tsa.example.com/tsa")
    }

    /// A passed probe stores the draft and records the verdict.
    @Test
    internal func verifiedProbeStoresTheDraft() async throws {
      let defaults = try Self.freshDefaults()
      let model = TimestampSettingsModel(
        defaults: defaults,
        prober: { _ in try await Task.sleep(for: .milliseconds(1)) },
        autoTestDelay: .seconds(30)
      )
      model.draft = "http://tsa.example.com/tsa"
      await model.runTest()
      #expect(TimestampAuthorityStore.load(from: defaults) == "http://tsa.example.com/tsa")
      let verdict = try #require(
        TimestampAuthorityStore.verification(for: "http://tsa.example.com/tsa", in: defaults)
      )
      #expect(verdict.succeeded)
      #expect(model.verification == verdict)
      #expect(!model.testing)
    }

    /// A failed probe records the verdict and keeps the stored address.
    @Test
    internal func failedProbeLeavesTheStoredAddress() async throws {
      let defaults = try Self.freshDefaults()
      TimestampAuthorityStore.store("http://stored.example/tsa", in: defaults)
      let model = TimestampSettingsModel(
        defaults: defaults,
        prober: { _ in throw TimestampClient.Failure.authorityDeclined },
        autoTestDelay: .seconds(30)
      )
      model.draft = "http://typed.example/tsa"
      await model.runTest()
      #expect(TimestampAuthorityStore.load(from: defaults) == "http://stored.example/tsa")
      let verdict = try #require(
        TimestampAuthorityStore.verification(for: "http://typed.example/tsa", in: defaults)
      )
      #expect(!verdict.succeeded)
      #expect(verdict.badge == TimestampClient.Failure.unansweredBadgeSymbol)
      #expect(model.verification == verdict)
      #expect(!model.testing)
    }

    /// A probe without a connection records the offline badge.
    @Test
    internal func missingConnectionRecordsTheOfflineBadge() async throws {
      let defaults = try Self.freshDefaults()
      let model = TimestampSettingsModel(
        defaults: defaults,
        prober: { _ in throw URLError(.notConnectedToInternet) },
        autoTestDelay: .seconds(30)
      )
      model.draft = "http://tsa.example.com/tsa"
      await model.runTest()
      let verdict = try #require(
        TimestampAuthorityStore.verification(for: "http://tsa.example.com/tsa", in: defaults)
      )
      #expect(verdict.badge == TimestampClient.Failure.offlineBadgeSymbol)
      #expect(
        TimestampAuthorityStore.load(from: defaults) == TimestampAuthorityStore.defaultAuthority
      )
    }

    /// A probe finished after the draft moved on is discarded.
    @Test
    internal func supersededProbeIsDiscarded() async throws {
      let defaults = try Self.freshDefaults()
      let gate = TimestampSettingsProbeDoubles.ProbeGate()
      let model = TimestampSettingsModel(
        defaults: defaults,
        prober: { _ in
          if gate.nextCall() == 1 {
            await gate.suspend()
          }
        },
        autoTestDelay: .seconds(30)
      )
      model.draft = "http://first.example/tsa"
      let superseded = Task {
        await model.runTest()
      }
      var spins = 0
      while !gate.hasEntered {
        spins += 1
        try #require(spins < 200, "The first probe never started.")
        try await Task.sleep(for: .milliseconds(5))
      }
      model.draft = "http://second.example/tsa"
      await model.runTest()
      gate.release()
      await superseded.value
      #expect(
        TimestampAuthorityStore.verification(for: "http://first.example/tsa", in: defaults) == nil
      )
      let verdict = try #require(
        TimestampAuthorityStore.verification(for: "http://second.example/tsa", in: defaults)
      )
      #expect(verdict.succeeded)
      #expect(TimestampAuthorityStore.load(from: defaults) == "http://second.example/tsa")
    }

    /// A recorded verdict shows at once, then refreshes with a probe.
    @Test
    internal func recordedVerdictRefreshesWithAProbe() async throws {
      let defaults = try Self.freshDefaults()
      TimestampAuthorityStore.recordVerification(
        address: "http://tsa.example.com/tsa",
        failure: nil,
        date: Date(),
        in: defaults
      )
      let log = TimestampSettingsProbeDoubles.CallLog()
      let model = TimestampSettingsModel(
        defaults: defaults,
        prober: { target in await log.record(target) },
        autoTestDelay: .milliseconds(20)
      )
      model.draft = "http://tsa.example.com/tsa"
      model.draftChanged()
      #expect(model.verification?.succeeded == true)
      let targets = await Self.awaitTargets(log)
      #expect(targets == ["http://tsa.example.com/tsa"])
    }

    /// Whitespace around the draft is trimmed, not probed.
    @Test
    internal func draftChangedTrimsWhitespace() throws {
      let defaults = try Self.freshDefaults()
      let model = TimestampSettingsModel(
        defaults: defaults,
        prober: { _ in try await Task.sleep(for: .milliseconds(1)) },
        autoTestDelay: .seconds(30)
      )
      model.draft = "  http://tsa.example.com/tsa\n"
      model.draftChanged()
      #expect(model.draft == "http://tsa.example.com/tsa")
    }

    /// An unproven draft is probed after a pause, and stored when valid.
    @Test
    internal func autoTestProbesAfterAPause() async throws {
      let defaults = try Self.freshDefaults()
      let log = TimestampSettingsProbeDoubles.CallLog()
      let model = TimestampSettingsModel(
        defaults: defaults,
        prober: { target in await log.record(target) },
        autoTestDelay: .milliseconds(20)
      )
      model.draft = "http://tsa.example.com/tsa"
      model.draftChanged()
      let targets = await Self.awaitTargets(log)
      #expect(targets == ["http://tsa.example.com/tsa"])
      var spins = 0
      while model.verification == nil {
        spins += 1
        try #require(spins < 500, "The probe never recorded its verdict.")
        try await Task.sleep(for: .milliseconds(10))
      }
      #expect(TimestampAuthorityStore.load(from: defaults) == "http://tsa.example.com/tsa")
      #expect(model.verification?.succeeded == true)
    }

    /// Reverting drops the draft and shows the stored address.
    @Test
    internal func revertToStoredDropsTheDraft() throws {
      let defaults = try Self.freshDefaults()
      TimestampAuthorityStore.store("http://stored.example/tsa", in: defaults)
      let model = TimestampSettingsModel(
        defaults: defaults,
        prober: { _ in try await Task.sleep(for: .milliseconds(1)) },
        autoTestDelay: .seconds(30)
      )
      model.draft = "http://typed.example/tsa"
      model.revertToStored()
      #expect(model.draft == "http://stored.example/tsa")
    }

    /// Restore forgets the draft and shows the shipped address.
    @Test
    internal func restoreDefaultsClearsTheDraft() throws {
      let defaults = try Self.freshDefaults()
      TimestampAuthorityStore.store("http://tsa.example.com/tsa", in: defaults)
      let model = TimestampSettingsModel(
        defaults: defaults,
        prober: { _ in try await Task.sleep(for: .milliseconds(1)) },
        autoTestDelay: .seconds(30)
      )
      #expect(model.draft == "http://tsa.example.com/tsa")
      model.restoreDefaults()
      #expect(model.draft == TimestampAuthorityStore.defaultAuthority)
      #expect(
        TimestampAuthorityStore.load(from: defaults) == TimestampAuthorityStore.defaultAuthority
      )
    }
  }

#endif
