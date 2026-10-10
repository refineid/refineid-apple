// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing
import UserNotifications

@testable import RefineID

/// What turning Remote Access on asks for, by permission state.
@Suite
internal struct RemoteAccessPermissionsTests {
  /// A granted notification permission asks nothing.
  @Test
  internal func grantedNotificationsAskNothing() {
    for status in [UNAuthorizationStatus.authorized, .provisional] {
      #expect(RemoteAccessPermissions.notificationStep(for: status) == .alreadyAllowed)
    }
  }

  /// An undecided permission leaves the asking to the system prompt.
  @Test
  internal func undecidedNotificationsUseTheSystemPrompt() {
    #expect(RemoteAccessPermissions.notificationStep(for: .notDetermined) == .request)
  }

  /// A declined permission is offered through Settings, not asked again.
  @Test
  internal func declinedNotificationsOfferSettings() {
    #expect(RemoteAccessPermissions.notificationStep(for: .denied) == .showSettingsRow)
  }

  /// Local network is probed only until access has been seen.
  @Test
  internal func localNetworkProbesOnlyUntilSeen() {
    #expect(RemoteAccessPermissions.needsLocalNetworkProbe(seenBefore: false))
    #expect(!RemoteAccessPermissions.needsLocalNetworkProbe(seenBefore: true))
  }
}
