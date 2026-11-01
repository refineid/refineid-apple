// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Identifies the empty CryptoTokenKit token published for a
/// recognized card that still needs its factory credentials changed.
///
/// It deliberately carries no keychain items. Its presence is only
/// the extension's authoritative, event-driven answer to the app;
/// an unactivated card must never be exposed as a usable identity.
public enum ActivationTokenIdentity {
  /// The prefix reserved for activation-required token instance identifiers.
  public static let instancePrefix = "activation-required-"

  /// Returns a stable activation-required instance identifier for a slot.
  public static func instanceID(forSlotNamed slotName: String) -> String {
    let encoded =
      slotName.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "reader"
    return instancePrefix + encoded
  }

  /// The reader slot an activation token stands for, or nil when the
  /// identifier is not one.
  public static func slotName(tokenID: String) -> String? {
    guard let range = tokenID.range(of: ":" + instancePrefix) else { return nil }
    return String(tokenID[range.upperBound...]).removingPercentEncoding
  }

  /// Returns whether a CryptoTokenKit identifier represents activation state.
  public static func recognizes(tokenID: String) -> Bool {
    tokenID.contains(":" + instancePrefix)
  }
}
