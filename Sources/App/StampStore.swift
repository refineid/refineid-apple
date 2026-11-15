// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The user preference for adding a visible stamp to signed PDF documents.
///
/// When enabled, PDF signatures receive a visible stamp at the bottom of the
/// document advising verification of the electronic signature.
/// Gated by FEATURE_PDF_STAMP: when the feature is compiled out, the setting
/// always reports false and cannot be enabled.
internal enum StampStore: Sendable {
  /// The preferences key holding the switch.
  internal static let key = "stamp"

  /// Whether the stamp is enabled.
  ///
  /// When FEATURE_PDF_STAMP is not defined, always returns false.
  internal static func isEnabled(in defaults: UserDefaults) -> Bool {
    #if !FEATURE_PDF_STAMP
      return false
    #else
      return defaults.bool(forKey: key)
    #endif
  }

  /// Whether the stamp is enabled in standard preferences.
  internal static func isEnabled() -> Bool {
    isEnabled(in: .standard)
  }

  /// Sets whether the stamp is enabled.
  internal static func setEnabled(_ enabled: Bool, in defaults: UserDefaults) {
    #if !FEATURE_PDF_STAMP
      // Gated out, do not store
    #else
      defaults.set(enabled, forKey: key)
    #endif
  }

  /// Sets whether the stamp is enabled in standard preferences.
  internal static func setEnabled(_ enabled: Bool) {
    setEnabled(enabled, in: .standard)
  }

  /// Forgets the configured preference.
  internal static func reset(in defaults: UserDefaults) {
    defaults.removeObject(forKey: key)
  }

  /// Forgets the configured preference in standard preferences.
  internal static func reset() {
    reset(in: .standard)
  }
}
