// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(Network)
  import CardCore
  import dnssd
  import Network
  import XCTest

  /// Proves what a connection's state and path, or a name lookup's error,
  /// say about the local-network permission: only the privacy refusal reads
  /// as denied, and only a ready connection reads as allowed.
  internal final class LocalNetworkVerdictTests: XCTestCase {
    private static let unreachable = NWError.posix(.EHOSTUNREACH)
    private static let policyDenied = DNSServiceErrorType(kDNSServiceErr_PolicyDenied)
    private static let noSuchRecord = DNSServiceErrorType(kDNSServiceErr_NoSuchRecord)

    internal func testAPathRefusedTheLocalNetworkReadsDenied() {
      for state in [
        NWConnection.State.preparing, .waiting(Self.unreachable), .failed(Self.unreachable),
      ] {
        XCTAssertEqual(
          LocalNetworkVerdict.of(state: state, unsatisfiedReason: .localNetworkDenied), .denied,
          "\(state)")
      }
    }

    internal func testAReadyConnectionReadsAllowed() {
      XCTAssertEqual(
        LocalNetworkVerdict.of(state: .ready, unsatisfiedReason: .notAvailable), .allowed)
    }

    internal func testAnyOtherUnsatisfiedPathSaysNothing() {
      for reason in [NWPath.UnsatisfiedReason.notAvailable, .cellularDenied, .wifiDenied] {
        XCTAssertNil(
          LocalNetworkVerdict.of(state: .waiting(Self.unreachable), unsatisfiedReason: reason),
          "\(reason)")
      }
      XCTAssertNil(
        LocalNetworkVerdict.of(state: .waiting(Self.unreachable), unsatisfiedReason: nil))
    }

    internal func testAStateWithoutAPathSaysNothing() {
      for state in [NWConnection.State.setup, .cancelled] {
        XCTAssertNil(
          LocalNetworkVerdict.of(state: state, unsatisfiedReason: .localNetworkDenied), "\(state)")
      }
    }

    internal func testTheLookupPolicyRefusalReadsDenied() {
      XCTAssertEqual(LocalNetworkVerdict.of(resolutionError: Self.policyDenied), .denied)
      XCTAssertEqual(LocalNetworkVerdict.of(connectionError: .dns(Self.policyDenied)), .denied)
    }

    internal func testAnyOtherErrorSaysNothing() {
      XCTAssertNil(LocalNetworkVerdict.of(resolutionError: Self.noSuchRecord))
      XCTAssertNil(LocalNetworkVerdict.of(connectionError: .dns(Self.noSuchRecord)))
      XCTAssertNil(LocalNetworkVerdict.of(connectionError: Self.unreachable))
    }
  }
#endif
