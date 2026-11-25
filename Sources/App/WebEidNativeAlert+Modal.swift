// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit
  import Combine
  import Foundation

  /// Deadline, card-removal, and window-scoped modal abort helpers for
  /// ``WebEidNativeAlert``.
  extension WebEidNativeAlert {
    // MARK: Nested Types

    /// Tracks state for one running modal alert so deadline/cancel aborts
    /// target only this owned window.
    @MainActor
    internal final class ModalGuard {
      internal var didTimeOut = false
      internal var didRemoveCard = false
      private weak var window: NSWindow?
      private weak var field: NSSecureTextField?
      private weak var confirmButton: NSButton?
      private var retryTimer: Timer?

      internal init(window: NSWindow, field: NSSecureTextField?, confirmButton: NSButton?) {
        self.window = window
        self.field = field
        self.confirmButton = confirmButton
      }

      internal func clearAndDisableField() {
        field?.stringValue = ""
        field?.isEnabled = false
        if let field, let editor = window?.fieldEditor(false, for: field) as? NSTextView {
          editor.string = ""
        }
        confirmButton?.isEnabled = false
      }

      internal func requestAbort() {
        guard let window else { return }
        if NSApp.modalWindow === window {
          NSApp.abortModal()
          return
        }
        guard retryTimer == nil else { return }
        let timer = Timer(
          timeInterval: Layout.abortRetryIntervalSeconds,
          repeats: true
        ) { [weak self] activeTimer in
          MainActor.assumeIsolated {
            guard let self, let owned = self.window else {
              activeTimer.invalidate()
              return
            }
            if NSApp.modalWindow === owned {
              activeTimer.invalidate()
              self.retryTimer = nil
              NSApp.abortModal()
            }
          }
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
      }

      internal func invalidate() {
        retryTimer?.invalidate()
        retryTimer = nil
      }
    }

    // MARK: Static Functions

    internal static func runWithDeadline(
      _ alert: NSAlert,
      options: ModalOptions,
      isCancelled: () -> Bool
    ) -> ModalOutcome {
      let remaining = options.expiresAt.timeIntervalSinceNow
      guard remaining > 0 else { return .timedOut }
      guard !isCancelled() else { return .other }

      let modalGuard = ModalGuard(
        window: alert.window,
        field: options.field,
        confirmButton: options.confirmButton
      )
      activeGuard = modalGuard
      defer {
        modalGuard.invalidate()
        if activeGuard === modalGuard {
          activeGuard = nil
        }
      }

      let deadlineTimer = Timer(timeInterval: remaining, repeats: false) { _ in
        MainActor.assumeIsolated {
          modalGuard.didTimeOut = true
          modalGuard.clearAndDisableField()
          modalGuard.requestAbort()
        }
      }
      RunLoop.main.add(deadlineTimer, forMode: .common)
      defer { deadlineTimer.invalidate() }

      let presenceCancellable =
        options.observeCardRemoval
        ? observeCardRemoval(guard: modalGuard)
        : nil
      defer { presenceCancellable?.cancel() }

      NSApp.activate(ignoringOtherApps: true)
      let response = alert.runModal()
      return resolveOutcome(
        response: response,
        modalGuard: modalGuard,
        expiresAt: options.expiresAt,
        isCancelled: isCancelled
      )
    }

    private static func observeCardRemoval(guard modalGuard: ModalGuard) -> AnyCancellable {
      CardPresence.shared.$isReaderCardPresent
        .removeDuplicates()
        .dropFirst()
        .sink { present in
          if !present {
            modalGuard.didRemoveCard = true
            modalGuard.clearAndDisableField()
            modalGuard.requestAbort()
          }
        }
    }

    private static func resolveOutcome(
      response: NSApplication.ModalResponse,
      modalGuard: ModalGuard,
      expiresAt: Date,
      isCancelled: () -> Bool
    ) -> ModalOutcome {
      if modalGuard.didRemoveCard {
        return .cardRemoved
      }
      if modalGuard.didTimeOut || Date() >= expiresAt {
        return .timedOut
      }
      if isCancelled() {
        return .other
      }
      return response == .alertFirstButtonReturn ? .firstButton : .other
    }
  }

#endif
