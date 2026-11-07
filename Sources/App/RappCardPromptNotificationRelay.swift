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
  /// or for the holder to unlock the phone, this relay displays a temporary banner.
  /// As soon as the card is detected, the phone proceeds or the operation
  /// completes/cancels, the delivered notification is immediately removed so
  /// it does not clutter the Notification Center history. A session that ended with
  /// the custodian's withdrawal or the pairing's revocation takes the identity down.
  ///
  /// It listens on this process's own notification center only.
  @MainActor
  internal final class RappCardPromptNotificationRelay: NSObject, UNUserNotificationCenterDelegate {
    internal static let shared = RappCardPromptNotificationRelay()

    /// UserNotification request identifier of the transient prompt banner.
    internal static let notificationIdentifier = "fi.refineid.card.prompt.banner"
    private static let promptGracePeriodSeconds: TimeInterval = 1.5
    private static let cardPromptTitle = String(localized: "Your phone needs an ID card, please.")
    private static let unlockPromptTitle = String(localized: "Unlock your phone, please.")

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
      guard observers.isEmpty else { return }
      #if DEBUG
        guard !TestCredentialEnvironment.isTestMode else { return }
      #endif
      // The host RefineID application is the sole consumer of UserNotifications in this bundle.
      UNUserNotificationCenter.current().delegate = self

      observers = [
        observe(RappRequesterNotices.cardNeeded) { relay in
          relay.schedulePromptNotification()
        },
        // A locked phone waits only for its holder, so the banner shows at once.
        observe(RappRequesterNotices.unlockNeeded) { relay in
          relay.pendingPresentWorkItem?.cancel()
          relay.pendingPresentWorkItem = nil
          relay.postPromptNotification(title: Self.unlockPromptTitle)
        },
        observe(RappRequesterNotices.cardWaitEnded) { relay in
          relay.dismissPromptNotification()
        },
        observe(RappRequesterNotices.serviceWithdrawn) { _ in
          PersistentTokenRegistry.shared.holderWithdrew()
        },
        observe(RappRequesterNotices.pairingRevoked) { _ in
          PersistentTokenRegistry.shared.pairingEndNoticed(
            published: PersistentTokenRegistry.publishedPairID(), in: RappDeviceVault())
        },
      ]
    }

    /// Runs `handler` on the main actor for every notice `name` this process posts.
    private func observe(
      _ name: Notification.Name,
      _ handler: @escaping @MainActor (RappCardPromptNotificationRelay) -> Void
    ) -> any NSObjectProtocol {
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          handler(self)
        }
      }
    }

    private func schedulePromptNotification() {
      guard pendingPresentWorkItem == nil else { return }
      let workItem = DispatchWorkItem { [weak self] in
        guard let self else { return }
        MainActor.assumeIsolated {
          self.pendingPresentWorkItem = nil
          self.postPromptNotification(title: Self.cardPromptTitle)
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

    /// Posts the one prompt banner; a later title replaces an earlier one.
    private func postPromptNotification(title: String) {
      let content = UNMutableNotificationContent()
      content.title = title
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
