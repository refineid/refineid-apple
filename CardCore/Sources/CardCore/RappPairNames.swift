// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// App-side names and models for paired devices, keyed by pair identifier.
///
/// The pair record binds no display name; the reviewed peer's name and the
/// platform it described itself with, its model, are remembered here so the
/// paired list can say which device it is. A name or model is what remains
/// after trimming whitespace; a blank is none.
public enum RappPairNames: Sendable {
  // MARK: Static Properties

  internal static let key = "fi.refineid.rapp.pair-names"

  /// Where the peers' models are kept, apart from their names.
  internal static let modelKey = "fi.refineid.rapp.pair-models"
  private static let lock = NSLock()

  /// The suite test runs keep names in, apart from the app's own: a test
  /// host shares the app's bundle identifier and so its standard defaults.
  internal static let testSuiteName = "fi.refineid.tests.pair-names"

  /// Where names are kept.
  private static var store: UserDefaults {
    guard TestCredentialEnvironment.isTestMode,
      let suite = UserDefaults(suiteName: testSuiteName)
    else { return .standard }
    return suite
  }

  // MARK: Public API

  /// Remembers the reviewed peer's name for one completed pair; a blank
  /// name forgets the pair's name instead.
  public static func remember(_ name: String, pairID: Data) {
    write(trimmed(name), pairID: pairID, under: key)
  }

  /// The remembered name, or nil for a pair whose peer left none.
  public static func name(forPairID pairID: Data) -> String? {
    stored(under: key)[pairID.base64EncodedString()].flatMap(trimmed)
  }

  /// Remembers the platform the reviewed peer described itself with for
  /// one completed pair; a blank forgets the pair's model instead.
  public static func rememberModel(_ model: String, pairID: Data) {
    write(trimmed(model), pairID: pairID, under: modelKey)
  }

  /// The remembered model, or nil for a pair whose peer left none.
  public static func model(forPairID pairID: Data) -> String? {
    stored(under: modelKey)[pairID.base64EncodedString()].flatMap(trimmed)
  }

  /// Drops the name and model of a removed pair.
  public static func forget(pairID: Data) {
    write(nil, pairID: pairID, under: key)
    write(nil, pairID: pairID, under: modelKey)
  }

  /// Drops every remembered name and model, orphans included.
  public static func forgetAll() {
    store.removeObject(forKey: key)
    store.removeObject(forKey: modelKey)
  }

  // MARK: Private Helpers

  private static func trimmed(_ name: String) -> String? {
    let kept = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return kept.isEmpty ? nil : kept
  }

  /// Sets or, for nil, removes the entry for `pairID` in the map under
  /// `mapKey`.
  private static func write(_ value: String?, pairID: Data, under mapKey: String) {
    let entries: [String: String] = {
      lock.lock()
      defer { lock.unlock() }
      var current = stored(under: mapKey)
      current[pairID.base64EncodedString()] = value
      return current
    }()
    store.set(entries, forKey: mapKey)
  }

  private static func stored(under mapKey: String) -> [String: String] {
    store.dictionary(forKey: mapKey) as? [String: String] ?? [:]
  }
}
