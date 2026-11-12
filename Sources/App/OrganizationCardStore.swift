// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Whether setup treats the card as an organization card.
///
/// Off means a personal card: the prompt takes exactly the six printed
/// digits and starts its hold on the sixth. On means an organization
/// card: the prompt takes its PIN 1 of four to twelve digits instead.
/// Either way the card on the antenna has the last word once the hold
/// runs. Written by the Settings app; nothing stored means off.
internal enum OrganizationCardStore: Sendable {
  /// The preferences key holding the switch.
  internal static let key = "organizationCardEnabled"

  /// The switch as stored, or off when nothing is stored.
  internal static func load(from defaults: UserDefaults) -> Bool {
    defaults.bool(forKey: Self.key)
  }
}
