// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation

  /// The keys the app's runtime settings live under, in one place so a
  /// window and the Settings pane bind the same stored value.
  ///
  /// `UserDefaults`-backed through `@AppStorage`; a change in Settings
  /// reaches every window that reads the key.
  internal enum AppSettings {
    /// Whether contactless cards are served: the CAN entry appears and
    /// numbers are offered only when this is on.
    ///
    /// Off by default. Contactless is the rare case - a card presented
    /// on the antenna rather than inserted - and the holder who wants
    /// it turns it on in Settings; contact readers need no setting.
    internal static let contactlessEnabled = "contactlessEnabled"

    /// Whether the holder permits the local web signing server.
    ///
    /// Off by default.
    internal static let scsEnabled = "fi.refineid.scs.enabled"

    /// Whether automatic same-account device pairing via iCloud is enabled.
    ///
    /// On by default. Devices sharing the same Apple Account securely
    /// establish Noise sessions automatically without pairing codes.
    internal static let autoPairingEnabled = "autoPairingEnabled"
  }

#endif
