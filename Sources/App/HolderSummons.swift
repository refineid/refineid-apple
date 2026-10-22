// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import Foundation
  import UIKit
  import UserNotifications

  /// Brings the holder to the phone when a card command needs the
  /// near-field card while the app is in the background (CC-69).
  ///
  /// Core NFC opens a reader session only for an app in the foreground. The
  /// summons posts a time-sensitive notification naming the computer that
  /// asks, and waits until the app is active, the limit passes, or the
  /// session that asked ends. Tapping the notification brings the app
  /// forward; the card is then commanded as from the foreground. Only the
  /// operation holding the card summons, and a session that ends takes
  /// down its own summons and no other.
  @MainActor
  internal final class HolderSummons {
    internal static let shared = HolderSummons()

    /// How long a summoned holder has to bring the app forward, in
    /// seconds.
    ///
    /// Inside a requester's interactive operation lifetime of 120 seconds,
    /// less the near-field card wait of 20 seconds that follows, so a
    /// holder who answers in time still has the card read before the
    /// requester gives up.
    private static let limitSeconds = 90

    private static let notificationPrefix = "rapp-card-"

    /// How long a summoned holder has to bring the app forward.
    internal static var limit: Duration {
      .seconds(limitSeconds)
    }

    private var waiting: [UUID: CheckedContinuation<Bool, Never>] = [:]
    /// The session each summons was made for.
    private var owners: [UUID: UUID] = [:]
    private var activationObserver: (any NSObjectProtocol)?

    private init() {
      activationObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
      ) { _ in
        MainActor.assumeIsolated { Self.shared.resumeAll(true) }
      }
    }

    /// Asks the holder to bring the app forward for `requester`, on behalf
    /// of the session `owner`; true once the app is active, false when the
    /// limit passed or the session ended first.
    internal func summon(requester: String, owner: UUID) async -> Bool {
      guard UIApplication.shared.applicationState != .active else { return true }
      let ticket = UUID()
      post(ticket, requester: requester)
      let came = await withCheckedContinuation { continuation in
        waiting[ticket] = continuation
        owners[ticket] = owner
        Task { @MainActor in
          try? await Task.sleep(for: Self.limit)
          self.resume(ticket, false)
        }
      }
      remove(ticket)
      return came
    }

    /// Ends the summons of the session `owner`: it is gone.
    internal func cancel(owner: UUID) {
      for (ticket, ticketOwner) in owners where ticketOwner == owner {
        resume(ticket, false)
      }
    }

    /// Ends every summons: serving stopped.
    internal func cancelAll() {
      resumeAll(false)
    }

    private func resume(_ ticket: UUID, _ came: Bool) {
      owners.removeValue(forKey: ticket)
      waiting.removeValue(forKey: ticket)?.resume(returning: came)
    }

    private func resumeAll(_ came: Bool) {
      let all = waiting
      waiting.removeAll()
      owners.removeAll()
      for continuation in all.values {
        continuation.resume(returning: came)
      }
    }

    private func post(_ ticket: UUID, requester: String) {
      let content = UNMutableNotificationContent()
      content.title = "RefineID"
      content.body = String(localized: "\(requester) needs your identity card.")
      content.sound = .default
      // The paired computer is waiting now; a Focus may still silence it.
      content.interruptionLevel = .timeSensitive
      UNUserNotificationCenter.current().add(
        UNNotificationRequest(
          identifier: Self.notificationPrefix + ticket.uuidString, content: content,
          trigger: nil))
    }

    private func remove(_ ticket: UUID) {
      let identifier = Self.notificationPrefix + ticket.uuidString
      let center = UNUserNotificationCenter.current()
      center.removePendingNotificationRequests(withIdentifiers: [identifier])
      center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
  }
#endif
