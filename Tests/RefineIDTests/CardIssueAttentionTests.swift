// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import RefineIDTestHost

  @MainActor
  @Suite
  internal struct CardIssueAttentionTests {
    @MainActor
    private final class Harness {
      var windowVisible = false
      var presentCount = 0
      var probeCount = 0
      var safariRefreshCount = 0
      var clearCount = 0

      func makeAttention(suppressInitialCard: Bool) -> CardIssueAttention {
        CardIssueAttention(
          hooks: CardIssueAttention.Hooks(
            isStatusWindowVisible: { [self] in windowVisible },
            presentStatusWindow: { [self] in presentCount += 1 },
            probeReader: { [self] in probeCount += 1 },
            refreshSafariExtension: { [self] in safariRefreshCount += 1 },
            clearCardState: { [self] in clearCount += 1 }
          ),
          suppressInitialCard: suppressInitialCard
        )
      }
    }

    private static let firstCard: UInt64 = 1
    private static let secondCard: UInt64 = 2
    private static let thirdCard: UInt64 = 3
    private static let singleCount = 1
    private static let doubleCount = 2
    private static let tripleCount = 3

    private static func snapshot(
      cardID: UInt64 = firstCard,
      present: Bool = true,
      ready: Bool = true,
      activation: Bool = false,
      report: Bool = true,
      level: CredentialRetryHealth.Level? = .pristine,
      pin2Change: Bool = false,
      estonian: Bool = true,
      safari: SafariWebEidExtensionStatus.State = .enabled,
      webEid: Bool = false,
      demo: Bool = false
    ) -> CardIssueAttention.Snapshot {
      CardIssueAttention.Snapshot(
        isDemoMode: demo,
        hasActiveWebEidRequest: webEid,
        hasCompletedInitialScan: true,
        cardInsertionID: cardID,
        isReaderCardPresent: present,
        defersRemoval: false,
        isTokenReady: ready,
        awaitsActivation: activation,
        hasRetryReport: report,
        retryHealthLevel: level,
        pin2RequiresChangeBeforeSigning: pin2Change,
        isEstonianCard: estonian,
        safariExtensionState: safari
      )
    }

    @Test
    internal func healthyCardProbesOnceAndStaysSilent() {
      let harness = Harness()
      let attention = harness.makeAttention(suppressInitialCard: false)

      attention.evaluate(Self.snapshot(report: false, level: nil, safari: .unknown))
      #expect(harness.probeCount == Self.singleCount)
      #expect(harness.presentCount == .zero)

      attention.evaluate(Self.snapshot(safari: .unknown))
      #expect(harness.safariRefreshCount == Self.singleCount)

      attention.evaluate(Self.snapshot(safari: .enabled))
      #expect(harness.presentCount == .zero)
    }

    @Test
    internal func disabledSafariExtensionOpensOncePerInsertionAndFastSwapResetsState() {
      let harness = Harness()
      let attention = harness.makeAttention(suppressInitialCard: false)

      let card1 = Self.snapshot(cardID: Self.firstCard, safari: .disabled)
      attention.evaluate(card1)
      attention.evaluate(card1)
      #expect(harness.presentCount == Self.singleCount)

      // Fast card swap (new insertion ID without observing an intermediate absent snapshot).
      let card2 = Self.snapshot(cardID: Self.secondCard, report: false, safari: .disabled)
      attention.evaluate(card2)
      #expect(harness.clearCount == Self.singleCount)
      #expect(harness.probeCount == Self.singleCount)
      #expect(harness.presentCount == Self.doubleCount)
    }

    @Test
    internal func pin2ChangeCriticalPinAndActivationAllTriggerPresentation() {
      let harness = Harness()
      let attention = harness.makeAttention(suppressInitialCard: false)

      attention.evaluate(Self.snapshot(cardID: Self.firstCard, pin2Change: true))
      #expect(harness.presentCount == Self.singleCount)

      attention.evaluate(Self.snapshot(cardID: Self.secondCard, level: .critical, estonian: false))
      #expect(harness.presentCount == Self.doubleCount)

      attention.evaluate(
        Self.snapshot(cardID: Self.thirdCard, ready: false, activation: true, report: false)
      )
      #expect(harness.presentCount == Self.tripleCount)
    }

    @Test
    internal func closingWindowMidProbePreventsLateReopen() {
      let harness = Harness()
      harness.windowVisible = true
      let attention = harness.makeAttention(suppressInitialCard: false)

      // Window is open while probing; user closes window before issue arrives.
      attention.evaluate(Self.snapshot(report: false, level: nil, safari: .unknown))
      harness.windowVisible = false
      attention.noteStatusWindowClosed()

      // Late issue report must not reopen the window for the same card.
      attention.evaluate(Self.snapshot(pin2Change: true, safari: .disabled))
      #expect(harness.presentCount == .zero)
    }

    @Test
    internal func webEidLaunchSuppressionClearsOnRemovalOrNewCard() {
      let harness = Harness()
      let attention = harness.makeAttention(suppressInitialCard: true)

      let issue = Self.snapshot(cardID: Self.firstCard, pin2Change: true)
      attention.evaluate(issue)
      #expect(harness.presentCount == .zero)
      #expect(harness.probeCount == .zero)

      attention.evaluate(Self.snapshot(cardID: Self.firstCard, present: false, ready: false))
      attention.evaluate(Self.snapshot(cardID: Self.secondCard, pin2Change: true))
      #expect(harness.presentCount == Self.singleCount)
    }

    @Test
    internal func failedProbesActiveWebEidAndDemoModeNeverLoopOrPresent() {
      let harness = Harness()
      let attention = harness.makeAttention(suppressInitialCard: false)

      let unknown = Self.snapshot(report: false, level: nil, safari: .unknown)
      attention.evaluate(unknown)
      attention.evaluate(unknown)
      #expect(harness.probeCount == Self.singleCount)
      #expect(harness.safariRefreshCount == Self.singleCount)

      attention.evaluate(
        Self.snapshot(cardID: Self.secondCard, level: .critical, pin2Change: true, webEid: true)
      )
      attention.evaluate(
        Self.snapshot(cardID: Self.thirdCard, level: .critical, pin2Change: true, demo: true)
      )
      #expect(harness.presentCount == .zero)
    }
  }

#endif
