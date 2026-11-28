// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit
  import CardCore
  import Combine
  import Foundation

  /// Watches card insertions even while RefineID is running windowless and
  /// brings the status window forward once per card insertion when the card
  /// requires holder action (unchanged initial PIN 2, critical/blocked PIN,
  /// card awaiting activation, or an Estonian card with Safari Web eID
  /// disabled).
  ///
  /// Healthy cards stay completely silent; closing the window while the same
  /// card remains inserted never re-opens it. Each inserted card triggers at
  /// most one background retry probe and one Safari extension state check.
  @MainActor
  internal final class CardIssueAttention {
    internal struct Snapshot: Equatable {
      internal let isDemoMode: Bool
      internal let hasActiveWebEidRequest: Bool
      internal let hasCompletedInitialScan: Bool
      internal let cardInsertionID: UInt64
      internal let isReaderCardPresent: Bool
      internal let defersRemoval: Bool
      internal let isTokenReady: Bool
      internal let awaitsActivation: Bool
      internal let hasRetryReport: Bool
      internal let retryHealthLevel: CredentialRetryHealth.Level?
      internal let pin2RequiresChangeBeforeSigning: Bool
      internal let isEstonianCard: Bool
      internal let safariExtensionState: SafariWebEidExtensionStatus.State
    }

    internal struct Hooks {
      internal let isStatusWindowVisible: @MainActor () -> Bool
      internal let presentStatusWindow: @MainActor () -> Void
      internal let probeReader: @MainActor () -> Void
      internal let refreshSafariExtension: @MainActor () -> Void
      internal let clearCardState: @MainActor () -> Void
    }

    internal static let shared = CardIssueAttention()

    internal static var isAutomatedLaunch: Bool {
      if RefineIDApp.hostsUnitTests { return true }
      #if DEBUG
        return DebugLaunchModes.selected() != nil || TestCredentialEnvironment.isTestMode
      #else
        return false
      #endif
    }

    internal var cancellables: Set<AnyCancellable> = []
    internal var started = false
    private let hooks: Hooks
    private var suppressInitialCard = false
    private var lastSeenCardInsertionID: UInt64?
    private var presentedForCurrentCard = false
    private var probedForCurrentCard = false
    private var queriedSafariForCurrentCard = false

    private convenience init() {
      self.init(
        hooks: Hooks(
          isStatusWindowVisible: Self.liveIsStatusWindowVisible,
          presentStatusWindow: Self.livePresentStatusWindow,
          probeReader: { CredentialRetryHealth.shared.refreshFromReaderIfNeeded() },
          refreshSafariExtension: { SafariWebEidExtensionStatus.shared.refresh() },
          clearCardState: {
            CredentialRetryHealth.shared.clear()
            SafariWebEidExtensionStatus.shared.reset()
          }
        ),
        suppressInitialCard: false
      )
    }

    internal init(hooks: Hooks, suppressInitialCard: Bool) {
      self.hooks = hooks
      self.suppressInitialCard = suppressInitialCard
    }

    /// Whether a card state requires bringing RefineID's window to the holder.
    internal static func needsPresentation(for snapshot: Snapshot) -> Bool {
      guard
        !snapshot.isDemoMode,
        !snapshot.hasActiveWebEidRequest,
        snapshot.isReaderCardPresent
      else {
        return false
      }
      if snapshot.awaitsActivation {
        return true
      }
      guard snapshot.isTokenReady else {
        return false
      }
      if snapshot.pin2RequiresChangeBeforeSigning || snapshot.retryHealthLevel == .critical {
        return true
      }
      return snapshot.isEstonianCard && snapshot.safariExtensionState == .disabled
    }

    private static func liveStatusWindow() -> NSWindow? {
      NSApp.windows.first { $0.identifier?.rawValue == RefineIDApp.statusWindowID }
    }

    private static func liveIsStatusWindowVisible() -> Bool {
      liveStatusWindow()?.isVisible == true
    }

    private static func livePresentStatusWindow() {
      if let existing = liveStatusWindow() {
        existing.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
      }
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      NSWorkspace.shared.openApplication(
        at: Bundle.main.bundleURL,
        configuration: configuration,
        completionHandler: nil
      )
    }

    /// Starts observing card presence, token publication, retry health, and
    /// Safari extension state for the lifetime of the app.
    internal func start(suppressInitialCard: Bool) {
      guard !started, !Self.isAutomatedLaunch else { return }
      started = true
      self.suppressInitialCard = suppressInitialCard
      lastSeenCardInsertionID = nil
      resetPerCardFlags()
      subscribeToPublishedSources()
      observeObservableSources()
      evaluateCurrentState()
    }

    internal func stop() {
      started = false
      cancellables.removeAll()
    }

    /// Prevents a late probe or Safari check from reopening a window the holder
    /// just closed while the same card remains inserted.
    internal func noteStatusWindowClosed() {
      if lastSeenCardInsertionID != nil || CardPresence.shared.isReaderCardPresent {
        presentedForCurrentCard = true
      }
    }

    /// Re-evaluates after a Web eID prompt finishes so a card inserted during
    /// the ceremony can still be checked once the prompt closes.
    internal func noteWebEidRequestEnded() {
      guard started else { return }
      scheduleEvaluation()
    }

    /// Pure state transition evaluated on every relevant card or extension update.
    internal func evaluate(_ snapshot: Snapshot) {
      guard !snapshot.isDemoMode else { return }

      if !snapshot.isReaderCardPresent {
        handleCardAbsent(
          hasCompletedInitialScan: snapshot.hasCompletedInitialScan,
          defersRemoval: snapshot.defersRemoval
        )
        return
      }

      if let previousID = lastSeenCardInsertionID, previousID != snapshot.cardInsertionID {
        resetPerCardFlags()
        suppressInitialCard = false
        hooks.clearCardState()
      }
      lastSeenCardInsertionID = snapshot.cardInsertionID

      if suppressInitialCard {
        return
      }

      if !snapshot.hasActiveWebEidRequest, snapshot.isTokenReady {
        if !snapshot.hasRetryReport, !probedForCurrentCard {
          probedForCurrentCard = true
          hooks.probeReader()
        }
        if snapshot.isEstonianCard,
          snapshot.safariExtensionState == .unknown,
          !queriedSafariForCurrentCard
        {
          queriedSafariForCurrentCard = true
          hooks.refreshSafariExtension()
        }
      }

      guard Self.needsPresentation(for: snapshot) else { return }
      guard !presentedForCurrentCard else { return }
      presentedForCurrentCard = true
      if !hooks.isStatusWindowVisible() {
        hooks.presentStatusWindow()
      }
    }

    internal func handleCardAbsent(hasCompletedInitialScan: Bool, defersRemoval: Bool) {
      if hasCompletedInitialScan {
        suppressInitialCard = false
      }
      if !defersRemoval {
        lastSeenCardInsertionID = nil
        resetPerCardFlags()
        if !hooks.isStatusWindowVisible() {
          hooks.clearCardState()
        }
      }
    }

    private func resetPerCardFlags() {
      presentedForCurrentCard = false
      probedForCurrentCard = false
      queriedSafariForCurrentCard = false
    }
  }

#endif
