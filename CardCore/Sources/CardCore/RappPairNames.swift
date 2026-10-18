// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// App-side names for paired devices, keyed by pair identifier.
///
/// The pair record binds no display name; the reviewed peer's name is
/// remembered here so the paired list can say which device it is. A
/// name is what remains after trimming whitespace; a blank is no name.
public enum RappPairNames: Sendable {
  // MARK: Static Properties

  internal static let key = "fi.refineid.rapp.pair-names"
  private static let lock = NSLock()

  // MARK: Public API

  /// Remembers the reviewed peer's name for one completed pair; a blank
  /// name forgets the pair's name instead.
  public static func remember(_ name: String, pairID: Data) {
    guard let kept = trimmed(name) else {
      forget(pairID: pairID)
      return
    }
    let names: [String: String] = {
      lock.lock()
      defer { lock.unlock() }
      var current = stored()
      current[pairID.base64EncodedString()] = kept
      return current
    }()
    UserDefaults.standard.set(names, forKey: key)
  }

  /// The remembered name, or nil for a pair whose peer left none.
  public static func name(forPairID pairID: Data) -> String? {
    stored()[pairID.base64EncodedString()].flatMap(trimmed)
  }

  /// Drops the name of a removed pair.
  public static func forget(pairID: Data) {
    let names: [String: String] = {
      lock.lock()
      defer { lock.unlock() }
      var current = stored()
      current.removeValue(forKey: pairID.base64EncodedString())
      return current
    }()
    UserDefaults.standard.set(names, forKey: key)
  }

  /// Drops every remembered name, orphans included.
  public static func forgetAll() {
    UserDefaults.standard.removeObject(forKey: key)
  }

  // MARK: Private Helpers

  private static func trimmed(_ name: String) -> String? {
    let kept = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return kept.isEmpty ? nil : kept
  }

  private static func stored() -> [String: String] {
    UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
  }
}
