// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(Network)
  import CardCore
  import dnssd
  import Network
  import Testing

  /// Proves what a connection's state and path, or a name lookup's error,
  /// say about the local-network permission: only the privacy refusal reads
  /// as denied, and only a ready connection reads as allowed.
  @Suite(.serialized)
  internal final class LocalNetworkVerdictTests {
    private static let unreachable = NWError.posix(.EHOSTUNREACH)
    private static let policyDenied = DNSServiceErrorType(kDNSServiceErr_PolicyDenied)
    private static let noSuchRecord = DNSServiceErrorType(kDNSServiceErr_NoSuchRecord)

    @Test
    internal func testAPathRefusedTheLocalNetworkReadsDenied() {
      for state in [
        NWConnection.State.preparing, .waiting(Self.unreachable), .failed(Self.unreachable),
      ] {
        #expect(
          (LocalNetworkVerdict.of(state: state, unsatisfiedReason: .localNetworkDenied))
            == (.denied), "\(state)")
      }
    }

    @Test
    internal func testAReadyConnectionReadsAllowed() {
      #expect(
        (LocalNetworkVerdict.of(state: .ready, unsatisfiedReason: .notAvailable)) == (.allowed))
    }

    @Test
    internal func testAnyOtherUnsatisfiedPathSaysNothing() {
      for reason in [NWPath.UnsatisfiedReason.notAvailable, .cellularDenied, .wifiDenied] {
        #expect(
          (LocalNetworkVerdict.of(state: .waiting(Self.unreachable), unsatisfiedReason: reason))
            == nil, "\(reason)")
      }
      #expect(
        (LocalNetworkVerdict.of(state: .waiting(Self.unreachable), unsatisfiedReason: nil)) == nil)
    }

    @Test
    internal func testAStateWithoutAPathSaysNothing() {
      for state in [NWConnection.State.setup, .cancelled] {
        #expect(
          (LocalNetworkVerdict.of(state: state, unsatisfiedReason: .localNetworkDenied)) == nil,
          "\(state)")
      }
    }

    @Test
    internal func testTheLookupPolicyRefusalReadsDenied() {
      #expect((LocalNetworkVerdict.of(resolutionError: Self.policyDenied)) == (.denied))
      #expect((LocalNetworkVerdict.of(connectionError: .dns(Self.policyDenied))) == (.denied))
    }

    @Test
    internal func testAnyOtherErrorSaysNothing() {
      #expect((LocalNetworkVerdict.of(resolutionError: Self.noSuchRecord)) == nil)
      #expect((LocalNetworkVerdict.of(connectionError: .dns(Self.noSuchRecord))) == nil)
      #expect((LocalNetworkVerdict.of(connectionError: Self.unreachable)) == nil)
    }
  }
#endif
