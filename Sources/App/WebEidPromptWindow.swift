// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit
  import CardCore
  import SwiftUI

  /// Dedicated `NSWindow` hosting ``WebEidPromptView`` even when RefineID is
  /// running without its main status window.
  @MainActor
  internal final class WebEidPromptWindow: NSObject, NSWindowDelegate {
    // MARK: Nested Types

    private enum Layout {
      static let initialWidth: CGFloat = 420
      static let initialHeight: CGFloat = 220
    }

    // MARK: Properties

    private let model: WebEidPromptModel
    private let window: NSWindow
    private var dismissedProgrammatically = false

    // MARK: Lifecycle

    internal init(model: WebEidPromptModel) {
      self.model = model
      let created = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: Layout.initialWidth, height: Layout.initialHeight),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      created.title = model.windowTitle
      created.isReleasedWhenClosed = false
      created.level = .floating
      let hostingView = NSHostingView(rootView: WebEidPromptView(model: model))
      hostingView.sizingOptions = [.intrinsicContentSize]
      created.contentView = hostingView
      self.window = created
      super.init()
      window.delegate = self
    }

    // MARK: Functions

    internal func present() {
      window.center()
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
    }

    internal func closeProgrammatically() {
      dismissedProgrammatically = true
      window.delegate = nil
      window.close()
    }

    internal func windowShouldClose(_: NSWindow) -> Bool {
      !model.isSubmitting
    }

    internal func windowWillClose(_: Notification) {
      guard !dismissedProgrammatically else { return }
      model.cancel()
    }
  }

#endif
