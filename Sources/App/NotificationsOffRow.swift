// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import SwiftUI

  /// The row shown while notifications stay declined.
  internal struct NotificationsOffRow: View {
    @ObservedObject private var state = NotificationPermissionState.shared

    internal var body: some View {
      Group {
        if state.isDeclined {
          HStack {
            Text(String(localized: "Notifications are off."))
              .foregroundStyle(.secondary)
            Spacer()
            Button(String(localized: "Open Settings")) {
              RemoteAccessPermissions.openSettings()
            }
            .accessibilityIdentifier("notificationsOffSettings")
          }
        }
      }
      .onAppear { state.refresh() }
    }
  }
#endif
