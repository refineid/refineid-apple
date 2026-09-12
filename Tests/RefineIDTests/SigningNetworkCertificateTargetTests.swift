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
      "http://[64:ff9b:1::8.8.8.8]/status",
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

  /// Public literal AIA, CRL, and OCSP endpoints keep their HTTP(S)
  /// compatibility; hostname resolution happens only when a request is sent.
  @Test
  internal func certificateMaterialAcceptsPublicInitialAddresses() throws {
    for address in [
      "http://8.8.8.8/status",
      "https://[2001:4860:4860::8888]/status",
      "http://[64:ff9b::8.8.8.8]/status",
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

  /// A certificate-controlled HTTP hostname is converted to the exact
  /// vetted address before URLSession receives the request, so it cannot
  /// resolve the name a second time to a private target.
  @Test
  internal func certificateMaterialHttpHostnameIsPinnedToDnsAnswer() throws {
    let original = try SigningNetwork.postRequest(
      Data("ocsp".utf8),
      to: "http://ocsp.example:8080/status",
      contentType: "application/ocsp-request",
      credentials: nil,
      endpoint: .certificateMaterial
    )
    let pinned = try SigningNetwork.pinnedCertificateMaterialRequest(
      original,
      resolvingTo: [.ipv4(Data([8, 8, 8, 8]))]
    )

    #expect(pinned.url?.absoluteString == "http://8.8.8.8:8080/status")
    #expect(pinned.value(forHTTPHeaderField: "Host") == "ocsp.example:8080")
    #expect(pinned.httpBody == Data("ocsp".utf8))
  }

  /// An IPv6 DNS answer is rendered as a valid bracketed URL literal while
  /// retaining the certificate-published hostname in Host.
  @Test
  internal func certificateMaterialHttpHostnamePinsIpv6DnsAnswer() throws {
    let original = try SigningNetwork.postRequest(
      Data(),
      to: "http://ocsp.example/status",
      contentType: "application/ocsp-request",
      credentials: nil,
      endpoint: .certificateMaterial
    )
    let publicAddress = SigningNetwork.NumericAddress.ipv6(
      Data([
        32, 1, 72, 96, 72, 96, 0, 0,
        0, 0, 0, 0, 0, 0, 136, 136,
      ])
    )
    let pinned = try SigningNetwork.protectedCertificateMaterialRequest(
      original,
      resolvingTo: [publicAddress]
    )

    #expect(pinned.url?.absoluteString == "http://[2001:4860:4860::8888]/status")
    #expect(pinned.value(forHTTPHeaderField: "Host") == "ocsp.example")
  }

  /// Every DNS answer for a certificate hostname must be public.
  ///
  /// HTTPS keeps its hostname after that preflight so URLSession can retain
  /// SNI and certificate validation rather than being rewritten to a numeric
  /// URL.
  @Test
  internal func certificateMaterialDnsPreflightChecksAllAnswers() throws {
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
        resolvingTo: [
          .ipv4(Data([8, 8, 8, 8])),
          .ipv4(Data([127, 0, 0, 1])),
        ]
      )
    }
    let httpsRequest = try SigningNetwork.postRequest(
      Data(),
      to: "https://ocsp.example/status",
      contentType: "application/ocsp-request",
      credentials: nil,
      endpoint: .certificateMaterial
    )
    let preflighted = try SigningNetwork.protectedCertificateMaterialRequest(
      httpsRequest,
      resolvingTo: [.ipv4(Data([8, 8, 8, 8]))]
    )
    #expect(preflighted.url == httpsRequest.url)
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
