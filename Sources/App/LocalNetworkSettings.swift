// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

/// Where the holder allows this app the local network, and what the app
/// says while it is denied.
internal enum LocalNetworkSettings {
  #if os(macOS)
    /// The Privacy & Security pane of System Settings, with the Local
    /// Network anchor.
    ///
    /// A system that does not know the anchor opens the pane at its list,
    /// where Local Network is a row.
    private static let paneAddress =
      "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocalNetwork"
  #endif

  /// What the app says while the platform keeps it off the local network,
  /// naming where the holder allows it.
  internal static var deniedMessage: String {
    #if os(macOS)
      String(
        localized: """
          macOS is blocking RefineID from the local network. Allow it in \
          System Settings › Privacy & Security › Local Network.
          """)
    #else
      String(
        localized: """
          RefineID is not allowed to use the local network. Allow it in \
          Settings › Privacy & Security › Local Network.
          """)
    #endif
  }

  /// Opens the settings where the holder allows the local network: on the
  /// Mac the Privacy & Security pane, elsewhere this app's own settings,
  /// which carry its Local Network switch.
  @MainActor
  internal static func open() {
    #if os(macOS)
      guard let pane = URL(string: paneAddress) else { return }
      NSWorkspace.shared.open(pane)
    #elseif os(iOS)
      guard let settings = URL(string: UIApplication.openSettingsURLString) else { return }
      UIApplication.shared.open(settings)
    #endif
  }
}
