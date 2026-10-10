// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import Foundation
  import UIKit
  import UserNotifications

  /// Whether notifications are currently declined, kept fresh as the
  /// holder returns from Settings.
  @MainActor
  internal final class NotificationPermissionState: ObservableObject {
    internal static let shared = NotificationPermissionState()

    @Published internal private(set) var isDeclined = false

    private var activationObserver: NSObjectProtocol?

    private init() {
      activationObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.didBecomeActiveNotification,
        object: nil,
        queue: .main
      ) { _ in
        Task { @MainActor in Self.shared.refresh() }
      }
      refresh()
    }

    /// Reads the current authorization.
    internal func refresh() {
      Task { @MainActor in
        let status = await UNUserNotificationCenter.current()
          .notificationSettings().authorizationStatus
        let declined = RemoteAccessPermissions.notificationStep(for: status) == .showSettingsRow
        if isDeclined != declined {
          isDeclined = declined
        }
      }
    }
  }
#endif
