// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && !FEATURE_TIMESTAMP_CONFIG

  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// The macOS MVP asks only the shipped qualified service.
  ///
  /// With the Time Stamp pane compiled out, a value no pane can show
  /// cannot steer signing: the store ignores it and the client asks
  /// the shipped Sectigo authority.
  @Suite(.serialized)
  internal struct TimestampAuthorityGateTests {
    /// An isolated domain; the tests never touch the shared defaults.
    private static func freshDefaults() throws -> UserDefaults {
      let name = "TimestampAuthorityGateTests"
      let defaults = try #require(UserDefaults(suiteName: name))
      defaults.removePersistentDomain(forName: name)
      return defaults
    }

    @Test
    internal func storedAddressNeverSteersTheMac() throws {
      let defaults = try Self.freshDefaults()
      defaults.set("https://tsa.example.com/tsa", forKey: TimestampAuthorityStore.key)

      #expect(TimestampAuthorityStore.configured(in: defaults) == nil)
      #expect(
        TimestampAuthorityStore.load(from: defaults)
          == TimestampAuthorityStore.defaultAuthority
      )
      #expect(TimestampClient.authority == TimestampAuthorityStore.defaultAuthority)
    }

    @Test
    internal func theShippedAuthorityIsTheQualifiedSectigoService() {
      #expect(
        TimestampAuthorityStore.defaultAuthority
          == "http://timestamp.sectigo.com/qualified"
      )
      #expect(TimestampAuthorityStore.isUsable(TimestampClient.authority))
    }
  }

#endif
