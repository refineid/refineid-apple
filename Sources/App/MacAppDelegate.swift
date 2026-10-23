// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit

  /// Keeps the Mac app running with no window, and opens none at a
  /// login launch.
  ///
  /// The app holds the one Bluetooth link to the paired phone, and the
  /// remote card's token extension reaches the phone through it, so the
  /// app outlives its window: closing the window leaves it in the Dock,
  /// and only quitting ends it. Clicking the Dock icon or opening the
  /// app again brings the window back through SwiftUI's own reopen
  /// handling, which presents the status scene when no window is
  /// visible.
  ///
  /// SwiftUI presents the status window before the launch event is
  /// readable, so a login launch closes it here, in the same turn of
  /// the run loop, before it is ever drawn. The work the status screen
  /// starts once per run is started here instead, since no screen
  /// appears.
  ///
  /// Quitting while remote use is on turns it off first, and the app exits
  /// once the session's `service_withdrawn` close has left or
  /// ``QuitWithdrawal/bound`` has passed (RAPP v26.10.22 §4.5 item 8).
  @MainActor
  internal final class MacAppDelegate: NSObject, NSApplicationDelegate {
    internal func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
      false
    }

    internal func applicationShouldTerminate(_ sender: NSApplication)
      -> NSApplication.TerminateReply
    {
      #if REFINEID_REMOTE_CARD && REFINEID_STREAM_TRANSPORT
        guard
          let closes = QuitWithdrawal.begin(
            remoteUse: .shared, registry: .shared)
        else { return .terminateNow }
        QuitWithdrawal.wait(for: closes, atMost: QuitWithdrawal.bound) {
          sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
      #else
        return .terminateNow
      #endif
    }

    internal func applicationDidFinishLaunching(_: Notification) {
      if LoginItem.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent) {
        for window in NSApp.windows
        where window.identifier?.rawValue == RefineIDApp.statusWindowID {
          window.close()
        }
        DisplacedRemoteCardWithdrawal.performOnce()
        #if FEATURE_CONTACTLESS
          SealedCardSection.withdrawOfferedNumber()
        #endif
      }
      LoginItem.registerIfDue()
    }
  }

#endif
