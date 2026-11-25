// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation
  import Testing

  @testable import RefineIDTestHost

  @MainActor
  @Suite(.serialized, SharedDemoStateScope())
  internal struct SafariWebEidExtensionStatusTests {
    private static let estonianAllowance: UInt8 = 3

    @Test
    internal func transitionsBetweenUnknownDisabledAndEnabledAndIgnoresStaleCallbacks() {
      var completions: [@MainActor (SafariWebEidExtensionStatus.State) -> Void] = []
      var openedCount = 0
      let status = SafariWebEidExtensionStatus(
        queryState: { completion in completions.append(completion) },
        openExtensionPreferences: { openedCount += 1 }
      )

      #expect(status.state == .unknown)

      status.refresh()
      #expect(completions.count == 1)
      completions[0](.disabled)
      #expect(status.state == .disabled)

      status.refresh()
      #expect(completions.count == 2)
      status.reset()
      #expect(status.state == .unknown)

      // Late completion from before reset must be ignored.
      completions[1](.disabled)
      #expect(status.state == .unknown)

      status.refresh()
      completions[2](.enabled)
      #expect(status.state == .enabled)

      status.refresh()
      completions[3](.unknown)
      #expect(status.state == .unknown)

      status.openPreferences()
      #expect(openedCount == 1)
    }

    @Test
    internal func syncRefreshesWhenEligibleAndResetsWhenIneligible() {
      var completions: [@MainActor (SafariWebEidExtensionStatus.State) -> Void] = []
      let status = SafariWebEidExtensionStatus(
        queryState: { completion in completions.append(completion) },
        openExtensionPreferences: {
          // Unused by eligibility sync test.
        }
      )

      // Card identified before becoming ready: stays reset without querying.
      status.sync(eligible: false)
      #expect(completions.isEmpty)
      #expect(status.state == .unknown)

      // Card becomes ready: queries Safari and surfaces disabled state.
      status.sync(eligible: true)
      #expect(completions.count == 1)
      completions[0](.disabled)
      #expect(status.state == .disabled)

      // Entering demo mode or losing readiness resets and drops stale replies.
      status.sync(eligible: true)
      #expect(completions.count == 2)
      status.sync(eligible: false)
      #expect(status.state == .unknown)
      completions[1](.disabled)
      #expect(status.state == .unknown)
    }

    @Test
    internal func guideShowsOnlyForLiveReadyEstonianCardWhenExtensionIsDisabled() {
      #expect(
        SafariWebEidExtensionStatus.shouldShowGuide(
          isDemoMode: false,
          availability: .ready,
          isEstonianCard: true,
          extensionState: .disabled
        )
      )
      #expect(
        !SafariWebEidExtensionStatus.shouldShowGuide(
          isDemoMode: false,
          availability: .ready,
          isEstonianCard: false,
          extensionState: .disabled
        )
      )
      #expect(
        !SafariWebEidExtensionStatus.shouldShowGuide(
          isDemoMode: false,
          availability: .ready,
          isEstonianCard: true,
          extensionState: .enabled
        )
      )
      #expect(
        !SafariWebEidExtensionStatus.shouldShowGuide(
          isDemoMode: false,
          availability: .ready,
          isEstonianCard: true,
          extensionState: .unknown
        )
      )
      #expect(
        !SafariWebEidExtensionStatus.shouldShowGuide(
          isDemoMode: true,
          availability: .ready,
          isEstonianCard: true,
          extensionState: .disabled
        )
      )
      #expect(
        !SafariWebEidExtensionStatus.shouldShowGuide(
          isDemoMode: false,
          availability: .noCard,
          isEstonianCard: true,
          extensionState: .disabled
        )
      )
    }

    @Test
    internal func retryHealthTracksEstonianCardFlagAndClearsItOnRemoval() throws {
      let three = try #require(RetryCount(attemptsRemaining: Self.estonianAllowance))
      let health = CredentialRetryHealth.shared
      defer { health.clear() }

      health.update(
        CredentialProbeReport(
          pin1: .remaining(three),
          pin2: .remaining(three),
          puk: .remaining(three),
          pristineAllowance: Self.estonianAllowance,
          pin2RequiresChangeBeforeSigning: false,
          isEstonianCard: true
        )
      )
      #expect(health.isEstonianCard)

      health.clear()
      #expect(!health.isEstonianCard)
    }

    @Test
    internal func safariGuideStringsExistInFinnishAndSwedish() throws {
      let catalog = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/App/Localizable.xcstrings")
      let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: catalog))
      let strings = try #require((json as? [String: Any])?["strings"] as? [String: Any])
      let keys = [
        "Enable the RefineID Web eID extension in Safari to log in with an Estonian ID card.",
        "Open Safari Settings…",
      ]
      for key in keys {
        let entry = try #require(strings[key] as? [String: Any], "missing \(key)")
        let localizations = try #require(entry["localizations"] as? [String: Any])
        for language in ["fi", "sv"] {
          let localization = try #require(localizations[language] as? [String: Any])
          let unit = try #require(localization["stringUnit"] as? [String: Any])
          let value = try #require(unit["value"] as? String)
          #expect(!value.isEmpty, "\(language) empty for \(key)")
        }
      }
    }
  }

#endif
