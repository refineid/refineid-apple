// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineID

/// Direct checks for certificate-controlled endpoint policy.
@Suite
internal struct SigningNetworkCertificateTargetTests {
  /// Certificate extensions are not allowed to direct the app toward a
  /// private, local, link-local, multicast, or documentation endpoint.
  @Test
  internal func certificateMaterialRejectsNonPublicInitialAddresses() {
    for address in [
      "http://localhost/status",
      "http://service.localhost/status",
      "http://127.0.0.1/status",
      "http://10.0.0.1/status",
      "http://100.64.0.1/status",
      "http://169.254.1.1/status",
      "http://172.16.0.1/status",
      "http://192.0.2.1/status",
      "http://192.168.0.1/status",
      "http://198.18.0.1/status",
      "http://198.51.100.1/status",
      "http://203.0.113.1/status",
      "http://224.0.0.1/status",
      "http://[::1]/status",
      "http://[::127.0.0.1]/status",
      "http://[::ffff:127.0.0.1]/status",
      "http://[fc00::1]/status",
      "http://[fe80::1]/status",
      "http://[fec0::1]/status",
      "http://[ff02::1]/status",
      "http://[2001:db8::1]/status",
      "http://[64:ff9b:1::10.0.0.1]/status",
      "http://[64:ff9b::127.0.0.1]/status",
    ] {
      #expect(throws: SigningNetwork.Failure.unsafeAddress) {
        _ = try SigningNetwork.postRequest(
          Data(),
          to: address,
          contentType: "application/ocsp-request",
          credentials: nil,
          endpoint: .certificateMaterial
        )
      }
    }
  }

  /// Public AIA, CRL, and OCSP hostnames keep their HTTP(S)
  /// compatibility; hostname resolution happens only when a request is sent.
  @Test
  internal func certificateMaterialAcceptsPublicInitialHostnames() throws {
    for address in [
      "http://ocsp.example/status",
      "https://ocsp.example/status",
    ] {
      let request = try SigningNetwork.postRequest(
        Data(),
        to: address,
        contentType: "application/ocsp-request",
        credentials: nil,
        endpoint: .certificateMaterial
      )
      #expect(request.url?.absoluteString == address)
    }
  }

  /// A certificate hostname whose DNS answers are not all public is
  /// refused before dispatch, as is an empty answer set.
  @Test
  internal func certificateMaterialDnsPreflightRefusesNonPublicAnswers() throws {
    let httpRequest = try SigningNetwork.postRequest(
      Data(),
      to: "http://ocsp.example/status",
      contentType: "application/ocsp-request",
      credentials: nil,
      endpoint: .certificateMaterial
    )

    #expect(throws: SigningNetwork.Failure.unsafeAddress) {
      _ = try SigningNetwork.protectedCertificateMaterialRequest(
        httpRequest,
        resolvingTo: [.ipv4(Data([127, 0, 0, 1]))]
      )
    }
    #expect(throws: SigningNetwork.Failure.unsafeAddress) {
      _ = try SigningNetwork.protectedCertificateMaterialRequest(
        httpRequest,
        resolvingTo: []
      )
    }
  }

  /// The response accumulator refuses the chunk containing byte `limit + 1`
  /// and never retains more than the configured byte budget.
  @Test
  internal func responseAccumulatorStopsAtLimitPlusOne() {
    var accumulator = SigningNetwork.BoundedResponseBody(limit: 4)
    let fits = accumulator.append(Data([1, 2, 3, 4]))
    let overflows = accumulator.append(Data([5]))

    #expect(fits)
    #expect(!overflows)
    #expect(accumulator.data == Data([1, 2, 3, 4]))
  }
}
