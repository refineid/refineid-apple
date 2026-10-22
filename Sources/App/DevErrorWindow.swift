// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)
  import AppKit
  import SwiftUI

  /// The development error window on the Mac: every recent error in full,
  /// in a floating panel of its own, so nothing is drawn over the app's
  /// window.
  ///
  /// It comes up by itself when an error arrives while it is closed, in
  /// front of every ordinary window and without taking the keyboard or
  /// activating the app: whatever the developer is typing into, here or in
  /// a browser, keeps the focus. It stays until the developer closes it,
  /// keeps showing while another app is in front, and remembers where it
  /// was put. The Window menu opens it on demand.
  @MainActor
  internal final class DevErrorWindow {
    // MARK: Nested Types

    /// The window's measurements.
    private enum Layout {
      static let width: CGFloat = 560
      static let height: CGFloat = 320
      static let minimumWidth: CGFloat = 320
      static let minimumHeight: CGFloat = 160
      static let screenMargin: CGFloat = 24
    }

    // MARK: Static Properties

    /// The one window of the process.
    internal static let shared = DevErrorWindow()

    /// Names the window for a UI test that opted in.
    internal static let accessibilityIdentifier = "dev-error-window"

    /// The window's title.
    private static let title = "Errors"

    /// The name its frame is kept under between launches.
    private static let frameName = "DevErrors"

    // MARK: Properties

    private var panel: NSPanel?

    // MARK: Lifecycle

    private init() {
      // The one shared instance only.
    }

    // MARK: Static Functions

    /// Puts a window with no remembered frame in the top trailing corner
    /// of the main screen.
    private static func placeInCorner(_ window: NSWindow) {
      guard let visible = NSScreen.main?.visibleFrame else {
        window.center()
        return
      }
      let size = window.frame.size
      window.setFrameOrigin(
        NSPoint(
          x: visible.maxX - size.width - Layout.screenMargin,
          y: visible.maxY - size.height - Layout.screenMargin))
    }

    // MARK: Functions

    /// Starts following the log, bringing the window up for every new
    /// error.
    internal func start() {
      guard DevErrorModel.isEnabled else { return }
      let model = DevErrorModel.shared
      model.onArrival = { [weak self] in
        self?.present()
      }
      model.start()
    }

    /// Puts the window in front of every ordinary window without making
    /// it key or activating the app.
    internal func present() {
      madePanel().orderFrontRegardless()
    }

    /// Opens the window for the keyboard, as the menu item does.
    internal func show() {
      madePanel().makeKeyAndOrderFront(nil)
    }

    /// The window, made on first use.
    ///
    /// A utility panel at the floating level, kept while closed so its
    /// frame and list survive, and left showing when the app is not in
    /// front: the token extensions fail while a browser is.
    private func madePanel() -> NSPanel {
      if let panel {
        return panel
      }
      let made = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
        styleMask: [.titled, .closable, .resizable, .utilityWindow],
        backing: .buffered,
        defer: true)
      made.title = Self.title
      made.isFloatingPanel = true
      made.hidesOnDeactivate = false
      made.isReleasedWhenClosed = false
      made.contentMinSize = NSSize(width: Layout.minimumWidth, height: Layout.minimumHeight)
      let content = NSHostingView(rootView: DevErrorList(model: DevErrorModel.shared))
      content.sizingOptions = []
      made.contentView = content
      made.setAccessibilityIdentifier(Self.accessibilityIdentifier)
      if !made.setFrameUsingName(Self.frameName) {
        Self.placeInCorner(made)
      }
      made.setFrameAutosaveName(Self.frameName)
      panel = made
      return made
    }
  }
#endif
