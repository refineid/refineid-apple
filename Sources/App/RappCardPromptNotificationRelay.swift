// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  import AppKit
  import CardCore
  import Foundation
  import UserNotifications

  /// Relays transient ID card prompts from the persistent token driver to macOS UserNotifications.
  ///
  /// When an authentication or signing request is waiting for the card on the phone,
  /// this relay displays a temporary banner. As soon as the card is detected or the
  /// operation completes/cancels, the delivered notification is immediately removed so
  /// it does not clutter the Notification Center history.
  @MainActor
  internal final class RappCardPromptNotificationRelay: NSObject, UNUserNotificationCenterDelegate {
    internal static let shared = RappCardPromptNotificationRelay()

    internal static let notificationIdentifier =
      RappCardPromptNotificationNames.userNotificationRequestIdentifier
    internal static let cardNeededDarwinNotification =
      RappCardPromptNotificationNames.cardNeededDarwinNotification
    internal static let cardDismissDarwinNotification =
      RappCardPromptNotificationNames.cardDismissDarwinNotification
    private static let promptGracePeriodSeconds: TimeInterval = 1.5

    private var distributedNeededObserver: (any NSObjectProtocol)?
    private var distributedDismissObserver: (any NSObjectProtocol)?
    private var pendingPresentWorkItem: DispatchWorkItem?

    override private init() {
      super.init()
    }

    internal func start() {
      let center = UNUserNotificationCenter.current()
      center.delegate = self
      center.requestAuthorization(options: [.alert]) { _, _ in
        // Authorization requested for user notifications.
      }

      distributedNeededObserver = DistributedNotificationCenter.default().addObserver(
        forName: Notification.Name(Self.cardNeededDarwinNotification),
        object: nil,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.schedulePromptNotification()
        }
      }

      distributedDismissObserver = DistributedNotificationCenter.default().addObserver(
        forName: Notification.Name(Self.cardDismissDarwinNotification),
        object: nil,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.dismissPromptNotification()
        }
      }
    }

    private func schedulePromptNotification() {
      guard pendingPresentWorkItem == nil else { return }
      let workItem = DispatchWorkItem { [weak self] in
        guard let self else { return }
        MainActor.assumeIsolated {
          self.pendingPresentWorkItem = nil
          self.postPromptNotification()
        }
      }
      pendingPresentWorkItem = workItem
      // Grace period of 1.5 seconds: if the card is already present and immediately
      // available, the operation completes smoothly without ever displaying a notification.
      DispatchQueue.main.asyncAfter(
        deadline: .now() + Self.promptGracePeriodSeconds,
        execute: workItem
      )
    }

    private func postPromptNotification() {
      let content = UNMutableNotificationContent()
      content.title = String(localized: "Your phone needs an ID card, please.")
      content.body = String(localized: "Please hold your ID card against the back of the phone.")
      // No sound by default on macOS

      let request = UNNotificationRequest(
        identifier: Self.notificationIdentifier,
        content: content,
        trigger: nil
      )
      UNUserNotificationCenter.current().add(request) { _ in
        // Prompt request submitted to notification center.
      }
    }

    private func dismissPromptNotification() {
      pendingPresentWorkItem?.cancel()
      pendingPresentWorkItem = nil
      let center = UNUserNotificationCenter.current()
      center.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
      center.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated internal func userNotificationCenter(
      _: UNUserNotificationCenter,
      willPresent _: UNNotification,
      withCompletionHandler completionHandler: (UNNotificationPresentationOptions) -> Void
    ) {
      completionHandler([.banner])
    }
  }
#endif
