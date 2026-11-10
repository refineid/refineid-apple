// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// The time-stamp authority store falls back to the shipped service
  /// whenever nothing usable is configured.
  ///
  /// Serialized: the tests share one isolated domain and take turns.
  @Suite(.serialized)
  internal struct TimestampAuthorityStoreTests {
    /// An isolated domain; the tests never touch the shared defaults.
    private static func freshDefaults() throws -> UserDefaults {
      let name = "TimestampAuthorityStoreTests"
      let defaults = try #require(UserDefaults(suiteName: name))
      defaults.removePersistentDomain(forName: name)
      return defaults
    }

    /// Nothing stored means the shipped qualified service.
    @Test
    internal func unsetLoadsTheDefault() throws {
      #expect(
        try TimestampAuthorityStore.load(from: Self.freshDefaults())
          == TimestampAuthorityStore.defaultAuthority
      )
    }

    /// An empty entry is not a service: the default answers instead.
    @Test
    internal func emptyLoadsTheDefault() throws {
      let defaults = try Self.freshDefaults()
      TimestampAuthorityStore.store("", in: defaults)

      #expect(
        TimestampAuthorityStore.load(from: defaults)
          == TimestampAuthorityStore.defaultAuthority
      )
    }

    /// A configured http service is asked as written.
    @Test
    internal func configuredHttpAuthorityRoundTrips() throws {
      let defaults = try Self.freshDefaults()
      let address = "http://tsa.example.com/tsa"
      TimestampAuthorityStore.store(address, in: defaults)

      #expect(TimestampAuthorityStore.load(from: defaults) == address)
    }

    /// A configured https service is asked as written.
    @Test
    internal func configuredHttpsAuthorityRoundTrips() throws {
      let defaults = try Self.freshDefaults()
      let address = "https://tsa.example.com/tsa"
      TimestampAuthorityStore.store(address, in: defaults)

      #expect(TimestampAuthorityStore.load(from: defaults) == address)
    }

    /// A non-URL entry never reaches the network; the default does.
    @Test
    internal func unusableSchemeLoadsTheDefault() throws {
      let defaults = try Self.freshDefaults()
      TimestampAuthorityStore.store("gopher://tsa.example.com/tsa", in: defaults)

      #expect(
        TimestampAuthorityStore.load(from: defaults)
          == TimestampAuthorityStore.defaultAuthority
      )
    }

    /// A scheme without a host never reaches the network either.
    @Test
    internal func missingHostLoadsTheDefault() throws {
      let defaults = try Self.freshDefaults()
      TimestampAuthorityStore.store("http:///missing-host", in: defaults)

      #expect(
        TimestampAuthorityStore.load(from: defaults)
          == TimestampAuthorityStore.defaultAuthority
      )
    }

    /// Restoring the defaults forgets the configured service.
    @Test
    internal func restoreDefaultsForgetsTheConfiguredService() throws {
      let defaults = try Self.freshDefaults()
      TimestampAuthorityStore.store("https://tsa.example.com/tsa", in: defaults)
      TimestampAuthorityStore.restoreDefaults(in: defaults)

      #expect(
        TimestampAuthorityStore.load(from: defaults)
          == TimestampAuthorityStore.defaultAuthority
      )
    }

    /// Usability is http or https with a host, nothing else.
    @Test
    internal func usabilityNamesHttpWithHost() {
      #expect(TimestampAuthorityStore.isUsable("http://tsa.example.com/tsa"))
      #expect(TimestampAuthorityStore.isUsable("https://tsa.example.com/tsa"))
      #expect(!TimestampAuthorityStore.isUsable(""))
      #expect(!TimestampAuthorityStore.isUsable("tsa.example.com/tsa"))
      #expect(!TimestampAuthorityStore.isUsable("ftp://tsa.example.com/tsa"))
      #expect(!TimestampAuthorityStore.isUsable("http:///missing-host"))
    }

    /// The client asks a usable service, configured or shipped.
    @Test
    internal func clientAuthorityIsUsable() {
      #expect(TimestampAuthorityStore.isUsable(TimestampClient.authority))
    }
  }

#endif
