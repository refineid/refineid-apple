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

    /// An empty entry removes the key: the default answers, and the
    /// Settings default shows again.
    @Test
    internal func emptyRemovesTheKey() throws {
      let defaults = try Self.freshDefaults()
      TimestampAuthorityStore.store("https://tsa.example.com/tsa", in: defaults)
      TimestampAuthorityStore.store("", in: defaults)

      #expect(
        TimestampAuthorityStore.load(from: defaults)
          == TimestampAuthorityStore.defaultAuthority
      )
      #expect(TimestampAuthorityStore.configured(in: defaults) == nil)
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

    /// A blank entry written past the store is swept, so the
    /// Settings default shows again.
    @Test
    internal func blankSweepRemovesDirectWrites() throws {
      let defaults = try Self.freshDefaults()
      defaults.set("", forKey: TimestampAuthorityStore.key)
      TimestampAuthorityStore.refreshDisplayAddress(in: defaults)

      #expect(defaults.string(forKey: TimestampAuthorityStore.key) == nil)
      defaults.set("   ", forKey: TimestampAuthorityStore.key)
      TimestampAuthorityStore.refreshDisplayAddress(in: defaults)

      #expect(defaults.string(forKey: TimestampAuthorityStore.key) == nil)
      TimestampAuthorityStore.store("https://tsa.example.com/tsa", in: defaults)
      TimestampAuthorityStore.refreshDisplayAddress(in: defaults)

      #expect(
        TimestampAuthorityStore.load(from: defaults) == "https://tsa.example.com/tsa"
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

    /// Usability is the signing network's border: http or https
    /// with a host, nothing else.
    @Test
    internal func usabilityNamesHttpWithHost() {
      #expect(TimestampAuthorityStore.isUsable("http://tsa.example.com/tsa"))
      #expect(TimestampAuthorityStore.isUsable("https://tsa.example.com/tsa"))
      #expect(!TimestampAuthorityStore.isUsable(""))
      #expect(TimestampAuthorityStore.isUsable("tsa.example.com/tsa"))
      #expect(!TimestampAuthorityStore.isUsable("ftp://tsa.example.com/tsa"))
      #expect(!TimestampAuthorityStore.isUsable("http:///missing-host"))
      #expect(!TimestampAuthorityStore.isUsable("http://:8080/tsa"))
      #expect(!TimestampAuthorityStore.isUsable("https://user:pass@tsa.example.com/tsa"))
    }

    /// Pasted whitespace is trimmed, not encoded or refused.
    @Test
    internal func whitespaceIsTrimmed() throws {
      #expect(TimestampAuthorityStore.isUsable("  https://tsa.example.com/tsa  "))
      let defaults = try Self.freshDefaults()
      TimestampAuthorityStore.store("  https://tsa.example.com/tsa  ", in: defaults)

      #expect(
        TimestampAuthorityStore.load(from: defaults) == "https://tsa.example.com/tsa"
      )
    }

    /// The raw configured address is what was stored, for callers
    /// that show the draft rather than the effective service.
    @Test
    internal func configuredReturnsTheDraft() throws {
      let defaults = try Self.freshDefaults()
      #expect(TimestampAuthorityStore.configured(in: defaults) == nil)
      TimestampAuthorityStore.store("not a service", in: defaults)

      #expect(TimestampAuthorityStore.configured(in: defaults) == "not a service")
      #expect(
        TimestampAuthorityStore.load(from: defaults)
          == TimestampAuthorityStore.defaultAuthority
      )
    }

    @Test
    internal func bareAddressResolvesToTheSameHttpService() throws {
      let defaults = try Self.freshDefaults()
      defaults.set("tsa.example.com/tsa", forKey: TimestampAuthorityStore.key)
      #expect(TimestampAuthorityStore.load(from: defaults) == "http://tsa.example.com/tsa")
      #expect(TimestampAuthorityStore.isUsable("tsa.example.com/tsa"))
    }

    @Test
    internal func httpPrefixIsOmittedOnlyFromTheEditingAddress() throws {
      let defaults = try Self.freshDefaults()
      TimestampAuthorityStore.store("http://tsa.example.com/tsa", in: defaults)
      #expect(TimestampAuthorityStore.configured(in: defaults) == "tsa.example.com/tsa")
      #expect(TimestampAuthorityStore.load(from: defaults) == "http://tsa.example.com/tsa")
      defaults.set("http://tsa.example.com/tsa", forKey: TimestampAuthorityStore.key)
      TimestampAuthorityStore.refreshDisplayAddress(in: defaults)
      #expect(TimestampAuthorityStore.configured(in: defaults) == "tsa.example.com/tsa")
      #expect(TimestampAuthorityStore.load(from: defaults) == "http://tsa.example.com/tsa")
    }

    @Test
    internal func explicitHttpsIsPreservedInTheEditorAndRequest() throws {
      let defaults = try Self.freshDefaults()
      TimestampAuthorityStore.store("https://tsa.example.com/tsa", in: defaults)
      TimestampAuthorityStore.refreshDisplayAddress(in: defaults)
      #expect(TimestampAuthorityStore.configured(in: defaults) == "https://tsa.example.com/tsa")
      #expect(TimestampAuthorityStore.load(from: defaults) == "https://tsa.example.com/tsa")
    }

    @Test
    internal func defaultDisplayAddressResolvesToTheShippedService() throws {
      let defaults = try Self.freshDefaults()
      defaults.set(TimestampAuthorityStore.defaultAddress, forKey: TimestampAuthorityStore.key)
      #expect(
        TimestampAuthorityStore.load(from: defaults) == TimestampAuthorityStore.defaultAuthority)
    }

    @Test
    internal func urlInThePathDoesNotBecomeTheAddressScheme() throws {
      let defaults = try Self.freshDefaults()
      let address = "http://tsa.example.com/tsa?source=https://example.com/"
      TimestampAuthorityStore.store(address, in: defaults)
      #expect(TimestampAuthorityStore.load(from: defaults) == address)
    }

    @Test
    internal func bareAddressCanIncludeAnExplicitPort() throws {
      let defaults = try Self.freshDefaults()
      TimestampAuthorityStore.store("tsa.example.com:8080/tsa", in: defaults)
      #expect(TimestampAuthorityStore.load(from: defaults) == "http://tsa.example.com:8080/tsa")
    }

    /// The client asks a usable service, configured or shipped.
    @Test
    internal func clientAuthorityIsUsable() {
      #expect(TimestampAuthorityStore.isUsable(TimestampClient.authority))
    }
  }

#endif
