// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// The card kind selected for the phone's NFC antenna.
///
/// Off means a personal card: the prompt takes exactly the six printed
/// digits and starts its hold on the sixth. On means an organization
/// card: the prompt takes its PIN 1 of four to twelve digits instead.
/// The setting selects the credential and identity; card failures never
/// select the other kind. Written by Settings; nothing stored means off.
///
/// A build without organization-card support
/// (``OrganizationCardSupport``) never resolves the stored switch to
/// an organization kind; the stored value itself is left as it is, so
/// a later supporting build finds the holder's choice intact.
internal enum OrganizationCardStore: Sendable {
  /// The preferences key holding the switch.
  internal static let key = "organizationCardEnabled"

  /// The kind used for NFC setup, operations and stored identity selection.
  internal static func kind(from defaults: UserDefaults) -> ContactlessCardKind {
    kind(from: defaults, organizationSupported: OrganizationCardSupport.isEnabled)
  }

  /// The kind for `defaults` under an explicit support answer.
  internal static func kind(
    from defaults: UserDefaults,
    organizationSupported: Bool
  ) -> ContactlessCardKind {
    (load(from: defaults) ? ContactlessCardKind.organization : .personal)
      .gated(organizationSupported: organizationSupported)
  }

  internal static func kind() -> ContactlessCardKind {
    kind(from: .standard)
  }

  /// Publishes the setting to the token extension before NFC can open.
  internal static func synchronize() {
    ContactlessCardKindStore.save(kind())
  }

  /// The switch as stored, or off when nothing is stored.
  internal static func load(from defaults: UserDefaults) -> Bool {
    defaults.bool(forKey: Self.key)
  }
}
