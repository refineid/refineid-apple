// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

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
  }

#endif
