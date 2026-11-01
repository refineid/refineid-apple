// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  import AppKit
  import CardCore
  import Foundation
  import UserNotifications

  /// Relays the notices this process's requester sessions post
  /// (``RappRequesterNotices``) to macOS UserNotifications and to the
  /// published identity.
  ///
  /// When an authentication or signing request is waiting for the card on the phone,
  /// this relay displays a temporary banner. As soon as the card is detected or the
  /// operation completes/cancels, the delivered notification is immediately removed so
  /// it does not clutter the Notification Center history. A session that ended with
  /// the custodian's withdrawal or the pairing's revocation takes the identity down.
  @MainActor
  internal final class RappCardPromptNotificationRelay: NSObject, UNUserNotificationCenterDelegate {
    internal static let shared = RappCardPromptNotificationRelay()

    /// UserNotification request identifier of the transient card prompt banner.
    internal static let notificationIdentifier = "fi.refineid.card.prompt.banner"
    private static let promptGracePeriodSeconds: TimeInterval = 1.5

    private var observers: [any NSObjectProtocol] = []
    private var pendingPresentWorkItem: DispatchWorkItem?

    override private init() {
      super.init()
    }

    /// Listens for the requester sessions' notices.
    ///
    /// Asks macOS for nothing; permission is asked once a pairing succeeds
    /// (``RemoteAccessPermissions/requestNotificationsIfUndecided()``).
    internal func start() {
      #if DEBUG
        guard !TestCredentialEnvironment.isTestMode else { return }
      #endif
      // The host RefineID application is the sole consumer of UserNotifications in this bundle.
      UNUserNotificationCenter.current().delegate = self

      observers = [
        observe(RappRequesterNotices.cardNeeded) { $0.schedulePromptNotification() },
        observe(RappRequesterNotices.cardWaitEnded) { $0.dismissPromptNotification() },
        observe(RappRequesterNotices.serviceWithdrawn) { _ in
          PersistentTokenRegistry.shared.holderWithdrew()
        },
        observe(RappRequesterNotices.pairingRevoked) { _ in
          guard let pairID = PersistentTokenRegistry.publishedPairID() else { return }
          PersistentTokenRegistry.shared.holderRevoked(pairID: pairID)
        },
      ]
    }

    private func observe(
      _ name: Notification.Name,
      _ handle: @escaping @MainActor (RappCardPromptNotificationRelay) -> Void
    ) -> any NSObjectProtocol {
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          handle(self)
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

    // Specifying [.banner] while omitting .list ensures the notification appears transiently
    // as a banner and is not persisted into Notification Center history (per Apple
    // UserNotifications documentation for UNNotificationPresentationOptions).

    nonisolated internal func userNotificationCenter(
      _: UNUserNotificationCenter,
      willPresent _: UNNotification,
      withCompletionHandler completionHandler: (UNNotificationPresentationOptions) -> Void
    ) {
      completionHandler([.banner])
    }
  }
#endif
