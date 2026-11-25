// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit
  import Foundation
  import Observation
  import RappRequester
  import SafariServices
  import SwiftUI

  /// Queries whether the RefineID Safari Web eID extension is enabled and opens
  /// Safari's Extensions settings directly to it when an Estonian eID card is
  /// present and the extension is turned off.
  ///
  /// Starts as `.unknown` and never prompts unless Safari explicitly reports
  /// `isEnabled == false`, so test hosts and non-Estonian cards never show a
  /// spurious warning.
  ///
  /// Uses the Swift `async` overload `stateOfSafariExtension(withIdentifier:)`
  /// instead of the completion-handler overload because Apple's Objective-C
  /// header marks the completion block `NS_SWIFT_UI_ACTOR` even though
  /// `SafariServices` invokes it on its background XPC queue, which triggers a
  /// Swift 6 main-actor isolation trap (`_dispatch_assert_queue_fail`).
  @MainActor
  @Observable
  internal final class SafariWebEidExtensionStatus {
    internal typealias StateQuery = @MainActor () async -> State
    internal typealias PreferencesOpener = @MainActor () -> Void

    internal enum State: Equatable {
      case unknown
      case enabled
      case disabled
    }

    @MainActor
    internal struct Observer: ViewModifier {
      internal let eligible: Bool
      internal let status: SafariWebEidExtensionStatus

      internal func body(content: Content) -> some View {
        content
          .onAppear { status.sync(eligible: eligible) }
          .onChange(of: eligible) { _, now in status.sync(eligible: now) }
          .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
          ) { _ in
            status.sync(eligible: eligible)
          }
      }
    }

    /// Bundle identifier of `RefineIDSafariExtension.appex`.
    internal static let extensionBundleIdentifier = "fi.refineid.ReFineID.safari-extension"

    internal static let shared = SafariWebEidExtensionStatus()

    internal private(set) var state: State = .unknown

    @ObservationIgnored internal private(set) var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private let queryState: StateQuery
    @ObservationIgnored private let openExtensionPreferences: PreferencesOpener

    private convenience init() {
      self.init(
        queryState: Self.liveStateQuery,
        openExtensionPreferences: Self.livePreferencesOpener
      )
    }

    internal init(
      queryState: @escaping StateQuery,
      openExtensionPreferences: @escaping PreferencesOpener
    ) {
      self.queryState = queryState
      self.openExtensionPreferences = openExtensionPreferences
    }

    /// Whether the current card state should query and potentially show the
    /// Safari Web eID extension guide.
    internal static func isEligible(
      isDemoMode: Bool,
      availability: IdentityAvailability,
      isEstonianCard: Bool
    ) -> Bool {
      !isDemoMode && availability == .ready && isEstonianCard
    }

    /// Whether the main window should guide the holder to enable the Safari
    /// Web eID extension.
    internal static func shouldShowGuide(
      isDemoMode: Bool,
      availability: IdentityAvailability,
      isEstonianCard: Bool,
      extensionState: State
    ) -> Bool {
      isEligible(
        isDemoMode: isDemoMode,
        availability: availability,
        isEstonianCard: isEstonianCard
      ) && extensionState == .disabled
    }

    internal static func liveStateQuery() async -> State {
      do {
        let extensionState = try await SFSafariExtensionManager.stateOfSafariExtension(
          withIdentifier: extensionBundleIdentifier
        )
        return extensionState.isEnabled ? .enabled : .disabled
      } catch {
        return .unknown
      }
    }

    private static func livePreferencesOpener() {
      SFSafariApplication.showPreferencesForExtension(
        withIdentifier: extensionBundleIdentifier,
        completionHandler: nil
      )
    }

    internal func sync(eligible: Bool) {
      if eligible {
        refresh()
      } else {
        reset()
      }
    }

    internal func refresh() {
      refreshTask?.cancel()
      generation &+= 1
      let requestGeneration = generation
      let query = queryState
      refreshTask = Task { @MainActor [weak self] in
        guard !Task.isCancelled else { return }
        let resolved = await query()
        guard let self, !Task.isCancelled, generation == requestGeneration else { return }
        state = resolved
        refreshTask = nil
      }
    }

    internal func reset() {
      refreshTask?.cancel()
      refreshTask = nil
      generation &+= 1
      state = .unknown
    }

    internal func openPreferences() {
      openExtensionPreferences()
    }
  }

#endif
