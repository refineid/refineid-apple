// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// The stamp switch reads off unless enabled.
  ///
  /// Serialized: the tests share one isolated domain and take turns.
  @Suite(.serialized)
  internal struct StampStoreTests {
    /// An isolated domain; the tests never touch the shared defaults.
    private static func freshDefaults() throws -> UserDefaults {
      let name = "StampStoreTests"
      let defaults = try #require(UserDefaults(suiteName: name))
      defaults.removePersistentDomain(forName: name)
      return defaults
    }

    /// Nothing stored means stamp is off.
    @Test
    internal func unsetLoadsOff() throws {
      let defaults = try Self.freshDefaults()
      #expect(!StampStore.isEnabled(in: defaults))
    }

    /// Setting and reading back the stamp preference.
    @Test(arguments: [true, false])
    internal func storedSwitchLoadsBack(enabled: Bool) throws {
      let defaults = try Self.freshDefaults()
      StampStore.setEnabled(enabled, in: defaults)
      #if FEATURE_PDF_STAMP
        #expect(StampStore.isEnabled(in: defaults) == enabled)
      #else
        #expect(!StampStore.isEnabled(in: defaults))
      #endif
    }

    /// Reset clears the preference back to default.
    @Test
    internal func resetClearsPreference() throws {
      let defaults = try Self.freshDefaults()
      StampStore.setEnabled(true, in: defaults)
      StampStore.reset(in: defaults)
      #expect(!StampStore.isEnabled(in: defaults))
    }
  }

#endif
