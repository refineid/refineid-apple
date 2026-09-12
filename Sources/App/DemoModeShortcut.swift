// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import UIKit

  /// The Home Screen action that starts a demonstration.
  ///
  /// Declared statically in `Config/RefineID-iOS-Info.plist`, so it is on
  /// the icon from the moment the app is installed and before it has ever
  /// been launched; its title is localized through
  /// `Sources/App/InfoPlist.xcstrings`.
  ///
  /// Pressing and holding the icon is the only way in, and it is a way in
  /// rather than a switch: ``DemoMode`` keeps no stored state, so quitting
  /// the app is what ends a demonstration.
  ///
  /// The action itself arrives at one of two places, and which one depends
  /// on whether the app was already running: ``DemoModeAppDelegate`` has
  /// it when the action launched the app, ``DemoModeSceneDelegate`` when
  /// it did not. Both answer it here.
  internal enum DemoModeShortcut {
    /// The `UIApplicationShortcutItemType` the plist declares.
    internal static let itemType = "fi.refineid.shortcut.demonstration"

    /// Starts a demonstration when the action taken is this one.
    ///
    /// Answers whether the action was recognized, which is what the scene
    /// delegate's completion handler reports.
    @discardableResult
    @MainActor
    internal static func perform(_ item: UIApplicationShortcutItem?) -> Bool {
      guard item?.type == Self.itemType else { return false }
      DemoMode.shared.activate(scenario: DemoMode.defaultScenario)
      return true
    }
  }

#endif
