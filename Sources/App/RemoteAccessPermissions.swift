// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import UserNotifications

#if os(iOS)
  import UIKit
#endif

/// The permissions Remote Access leans on, asked for only when the
/// system has no answer yet.
///
/// The system's own prompts carry the explanation, so nothing is shown
/// before them. Turning remote use on asks for the local network and
/// Bluetooth; notifications are asked once a pairing has succeeded.
/// Local network has no query API: a probe detects denial, and once it
/// has seen access the answer is kept for the install.
/// Notifications are read from their settings; a denial is shown as a
/// row on the Remote Access screen, never as an alert.
internal enum RemoteAccessPermissions {
  // MARK: Nested Types

  /// What turning Remote Access on does about notifications.
  internal enum NotificationStep: Equatable {
    /// Already allowed; nothing to do.
    case alreadyAllowed

    /// Undecided; the system prompt asks.
    case request

    /// Declined; the screen offers Settings.
    case showSettingsRow
  }

  // MARK: Static Properties

  #if os(iOS)
    private static let localNetworkSeenKey = "remoteAccess.localNetworkSeen"
  #endif

  // MARK: Static Functions

  /// The notification step for an authorization status.
  internal static func notificationStep(for status: UNAuthorizationStatus) -> NotificationStep {
    switch status {
    case .notDetermined:
      .request

    case .denied:
      .showSettingsRow

    default:
      .alreadyAllowed
    }
  }

  /// Whether a local-network check needs the probe at all.
  internal static func needsLocalNetworkProbe(seenBefore: Bool) -> Bool {
    !seenBefore
  }

  /// Asks for notification permission once a pairing has succeeded, and
  /// only while the holder has not answered yet.
  ///
  /// The phone's notifications summon the holder for a paired computer; the
  /// Mac's relay the phone's card prompts. Before a pairing neither has a
  /// reason the holder could connect the prompt to, so turning remote use on
  /// asks for nothing but the local network and Bluetooth.
  @MainActor
  internal static func requestNotificationsIfUndecided() async {
    #if DEBUG
      guard !TestCredentialEnvironment.isTestMode else { return }
    #endif
    #if os(iOS)
      guard SupportedCardTransports.offersNearField else { return }
      let options: UNAuthorizationOptions = [.alert, .sound, .badge]
    #else
      let options: UNAuthorizationOptions = [.alert]
    #endif
    let center = UNUserNotificationCenter.current()
    let status = await center.notificationSettings().authorizationStatus
    guard Self.notificationStep(for: status) == .request else { return }
    _ = try? await center.requestAuthorization(options: options)
    #if os(iOS)
      NotificationPermissionState.shared.refresh()
    #endif
  }

  #if os(iOS)
    /// Whether this app may use the local network, probing only until
    /// access has been seen once.
    @MainActor
    internal static func localNetworkAccess() async -> LocalNetworkAccessDetector.Access {
      let defaults = UserDefaults.standard
      let seen = defaults.bool(forKey: Self.localNetworkSeenKey)
      guard Self.needsLocalNetworkProbe(seenBefore: seen) else { return .allowed }
      let access = await LocalNetworkAccessDetector.currentAccess()
      if access == .allowed {
        defaults.set(true, forKey: Self.localNetworkSeenKey)
      }
      return access
    }

    /// Opens this app's page in Settings.
    @MainActor
    internal static func openSettings() {
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
    }
  #endif
}
