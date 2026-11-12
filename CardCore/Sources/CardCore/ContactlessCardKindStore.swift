// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Shares the phone's selected NFC kind with its token extension.
///
/// This preference contains no credential or card identity.
public enum ContactlessCardKindStore {
  private static let group = "group.fi.refineid.RefineID"
  private static let key = "organizationCardEnabled"

  /// Reads the kind published by the app, defaulting to personal.
  public static func load() -> ContactlessCardKind {
    load(from: UserDefaults(suiteName: group))
  }

  /// Publishes the selected kind without storing any credential.
  public static func save(_ kind: ContactlessCardKind) {
    save(kind, to: UserDefaults(suiteName: group))
  }

  internal static func load(from defaults: UserDefaults?) -> ContactlessCardKind {
    defaults?.bool(forKey: key) == true ? .organization : .personal
  }

  internal static func save(_ kind: ContactlessCardKind, to defaults: UserDefaults?) {
    defaults?.set(kind == .organization, forKey: key)
  }
}
