// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// The login keychain sweep runs until it has finished once.
  @Suite
  internal struct RappVaultFileKeychainSweepTests {
    private struct Refused: Error {}

    private static func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
      let suite = "fi.refineid.tests.file-keychain-sweep.\(UUID().uuidString)"
      let defaults = try #require(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      try body(defaults)
    }

    @Test("A finished sweep does not run again")
    internal func finishedSweepRunsOnce() throws {
      try Self.withDefaults { defaults in
        var runs = 0
        RappVaultFileKeychainSweep.run(defaults: defaults) { runs += 1 }
        RappVaultFileKeychainSweep.run(defaults: defaults) { runs += 1 }
        #expect(runs == 1)
      }
    }

    @Test("A failed sweep stays due at the next launch")
    internal func failedSweepStaysDue() throws {
      try Self.withDefaults { defaults in
        var runs = 0
        RappVaultFileKeychainSweep.run(defaults: defaults) {
          runs += 1
          throw Refused()
        }
        #expect(!defaults.bool(forKey: RappVaultFileKeychainSweep.doneKey))
        RappVaultFileKeychainSweep.run(defaults: defaults) { runs += 1 }
        #expect(runs == 2)
        #expect(defaults.bool(forKey: RappVaultFileKeychainSweep.doneKey))
      }
    }
  }
#endif
