// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// The organization-card switch reads off unless the Settings app
  /// stored on.
  ///
  /// Serialized: the tests share one isolated domain and take turns.
  @Suite(.serialized)
  internal struct OrganizationCardStoreTests {
    /// An isolated domain; the tests never touch the shared defaults.
    private static func freshDefaults() throws -> UserDefaults {
      let name = "OrganizationCardStoreTests"
      let defaults = try #require(UserDefaults(suiteName: name))
      defaults.removePersistentDomain(forName: name)
      return defaults
    }

    /// Nothing stored means a personal card.
    @Test
    internal func unsetLoadsOff() throws {
      #expect(!OrganizationCardStore.load(from: try Self.freshDefaults()))
    }

    /// A stored switch is what loads.
    @Test(arguments: [true, false])
    internal func storedSwitchLoadsBack(enabled: Bool) throws {
      let defaults = try Self.freshDefaults()
      defaults.set(enabled, forKey: OrganizationCardStore.key)
      #expect(OrganizationCardStore.load(from: defaults) == enabled)
    }

    /// A supporting build follows the stored switch.
    @Test(arguments: [true, false])
    internal func supportedKindFollowsTheSwitch(enabled: Bool) throws {
      let defaults = try Self.freshDefaults()
      defaults.set(enabled, forKey: OrganizationCardStore.key)
      #expect(
        OrganizationCardStore.kind(from: defaults, organizationSupported: true)
          == (enabled ? .organization : .personal))
    }

    /// A stale on-switch never yields an organization kind in a build
    /// without support, and gating leaves the stored value intact.
    @Test
    internal func staleSwitchIsGatedAndPreserved() throws {
      let defaults = try Self.freshDefaults()
      defaults.set(true, forKey: OrganizationCardStore.key)
      #expect(
        OrganizationCardStore.kind(from: defaults, organizationSupported: false) == .personal)
      #expect(OrganizationCardStore.load(from: defaults))
    }

    /// No configuration enables organization cards right now, so the
    /// build under test resolves a stored on-switch to personal.
    @Test
    internal func buildUnderTestHasNoOrganizationSupport() throws {
      #expect(!OrganizationCardSupport.isEnabled)
      let defaults = try Self.freshDefaults()
      defaults.set(true, forKey: OrganizationCardStore.key)
      #expect(OrganizationCardStore.kind(from: defaults) == .personal)
    }
  }

#endif
