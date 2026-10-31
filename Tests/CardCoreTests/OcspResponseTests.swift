// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// Authentication checks for a signed RFC 6960 BasicOCSPResponse.
@Suite
internal struct OcspResponseTests {
  /// Fixture decoding that keeps checked-in DER readable in source.
  private enum Fixture {
    /// Decodes an invariant base64 fixture without a forced unwrap.
    static func data(_ encoded: String) -> Data {
      Data(base64Encoded: encoded) ?? Data()
    }

    /// Validates a response under the test's fixed verification time.
    static func validate(
      _ response: Data,
      currentTime: Date = OcspResponseTests.currentTime
    ) throws -> OcspResponse.Validity {
      try OcspResponse.validate(
        response: response,
        certificate: OcspResponseTests.certificate,
        issuerCertificate: OcspResponseTests.issuerCertificate,
        nonce: OcspResponseTests.nonce,
        currentTime: currentTime
      )
    }
  }

  /// An RSA CA certificate used only for deterministic test material.
  internal static let issuerCertificate = Fixture.data(
    "MIIDMTCCAhmgAwIBAgIUJbkApYZwGc7mrZAmE2e0uFJT3qowDQYJKoZIhvcNAQELBQAwIDEeMBwGA1UEAwwVUmVGaW5lSUQg"
      + "T0NTUCBUZXN0IENBMB4XDTI2MDgwNDA3NTkyNFoXDTI3MDgwNDA3NTkyNFowIDEeMBwGA1UEAwwVUmVGaW5lSUQgT0NTUCBU"
      + "ZXN0IENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEApDfIC/AcjXDVLeDf9tJz6mr5tPJuUcDEpapUMwAXp9Gv"
      + "06ymXXXMkB70zonQplTFghHam3H4yjKlPPnoIWuBWoEcsmscaYkS8T5svq04FuBBo+CAc7ESgfkf4y1lQ/u3pXYFGNuy7jib"
      + "utMJVJXboIHHgGKNHBFtbT6rKunrYwIinqIHMwjMQUENKNrkjtR2WS98BpsNIFRp2qA3DAmTnDdnKy78eTGBaQFl71c704ke"
      + "9yJZWFG407xfWJq7ZFwKcC9Ag2ogoqHETZg3tf5hW0cxhz4USGwcfJvd6h7JQaSW+x4dr+wapGxnmR3JjGxOtbsnCWO7rYlh"
      + "5O0JUXoGIwIDAQABo2MwYTAdBgNVHQ4EFgQULkqS8sh01llm+fcid2vzgs9bs8owHwYDVR0jBBgwFoAULkqS8sh01llm+fci"
      + "d2vzgs9bs8owDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAYYwDQYJKoZIhvcNAQELBQADggEBAA6NXjp0LdQMQKmL"
      + "/NvKocgxQpByzX35Y2Fn83E1bfE1dDJQfHF9hw6TL4HwV+4ZL3pd9PQyP6vRet+ftjRs7soQTE2BJjoNqN8SJyAVrx5Hjinl"
      + "aF+HT0pBvF8UmtI8WrHvoVJvwg6GgjfXkaY1ky+u3/dsohore9YqocN5jUce8FL6Uq/mxwNJRhI5x3Nd0Rwh2WQdY0bM6tph"
      + "XR2QnKSLPXIVYbYBJcdigcacHp0G5bvjdk/bJPJK72HqQfMalvAwSbCMZcLCL9E+XAJtLFVrk5KT2eGmwTCS+boQN6Crd6cw"
      + "WNREVZZWgtwVervU/83K8nC0Vhi2FKhzx7yhUSY="
  )

  /// A leaf certificate directly issued by `issuerCertificate`.
  internal static let certificate = Fixture.data(
    "MIIDEjCCAfqgAwIBAgIUHY+6mluHtmm73OeBXU4tJv6yneYwDQYJKoZIhvcNAQELBQAwIDEeMBwGA1UEAwwVUmVGaW5lSUQg"
      + "T0NTUCBUZXN0IENBMB4XDTI2MDgwNDA3NTkyNFoXDTI3MDgwNDA3NTkyNFowIjEgMB4GA1UEAwwXUmVGaW5lSUQgT0NTUCBU"
      + "ZXN0IExlYWYwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDIch5n4JX00LIdb3v0RfeD8bgvn4XZRNxflAEes7VG"
      + "E5uQ6VqWpeIgjVKwjFUninnLhKGvjauG2jOfhtsn1tmxCgZpHj4Tnu9P0s3hkcShSp1UrOAZ/K/jDB7YSGWZoQl/vA4d0LzL"
      + "tG1N2SX9J0+lOMbmwqkdsO5RZL8ZEusqBgQUX6nHB+VmoR2DfdwzMEiIT0YMZBajBdyDHOOzY0Pv4xucCxOmpD/SDsZtKP3O"
      + "4QA0CUBssQ1HBnbRRCf/YFg5HzkPROOVoPwiyHh1lXCs26pwYKmebIkixTWraF+BPfpA3SFb5UDBpv+q+5N5XSFklpjzSmAE"
      + "nxJIbxWDiNuBAgMBAAGjQjBAMB0GA1UdDgQWBBT9/HnEEqK84ujoj0BgddwsY2GvUzAfBgNVHSMEGDAWgBQuSpLyyHTWWWb5"
      + "9yJ3a/OCz1uzyjANBgkqhkiG9w0BAQsFAAOCAQEAX1YfyL7VmUOuhS0qj7Y3pEOVb2rd15YQIf7xZifCYKViKn/JShfNkPWX"
      + "dZ+HZbBsCHtUkYFqQaAADdLqJityLRRlnq4ErRBvWH3KO9et/pIXKMZTO/mmjdoar47JXHC73qME4EbnvWevAehiARQEZOJa"
      + "7IxZXP0qbX4GtR8o/Fs8aK65z3NKYcVlUpzUyG02dV4CDBwJ6Eotjnjq2Zk50LX0FrThOWuxaLG7GxLR45d0nfSrKc0FYu5H"
      + "PZ2eXymir2xdrpQTYejzgKltkUN7gJrhdIMCyyQ792xjn8tjjvEbsqOvhkspnfOwnNAr4LqG0ow/Ue9MnGTzHF3AcwzpcQ=="
  )

  /// A direct-issuer response, signed with the test CA's RSA key.
  internal static let responseWithNextUpdate = Fixture.data(
    "MIICCAoBAKCCAgEwggH9BgkrBgEFBQcwAQEEggHuMIIB6jCB06EiMCAxHjAcBgNVBAMMFVJlRmluZUlEIE9DU1AgVGVzdCBD"
      + "QRgPMjAyNjA4MDQwNzU5NTRaMHcwdTBNMAkGBSsOAwIaBQAEFG8TmqI0pqWu0NCE1/B/fc+Dv+jtBBQuSpLyyHTWWWb59yJ3"
      + "a/OCz1uzygIUHY+6mluHtmm73OeBXU4tJv6yneaAABgPMjAyNjA4MDQwNzU5NTRaoBEYDzIwMjYwOTAzMDc1OTU0WqEjMCEw"
      + "HwYJKwYBBQUHMAECBBIEELRxQeGhU1Be42qlhSTtBQowDQYJKoZIhvcNAQELBQADggEBAHbw7l29FG+XvoQE2hw3VHv1n5WJ"
      + "aw7tc5aBr31B7j2oEBUqqzp+e4FszwCfE6O7UavXVRRzx6p9BK1if/QXw8sTnMTmNOJqVYYOcDa2WDMRple+6gO3bkibPBwW"
      + "xHWaj+OVmbE2Kqyw36e7+ily0Uy2C7eXVEGnf3dGBMUvZiXMMxB850oPkD65vHZ8UIiN6Ha72b69mYwcSIz0MVvoqir3jf3e"
      + "/bODrfWy+iW7tQ1sJ2n+qPZXTjurJ4RMpA3Awx+D1OdXz5FPzDm3exmwnvtZGCA2sWu/nzTEOX7/57FZVTdYB7AMsGnw5D2u"
      + "j2QSZJKqjs/kePWoNcT1zRoAZGE="
  )

  /// The same signed status with no `nextUpdate` field.
  private static let responseWithoutNextUpdate = Fixture.data(
    "MIIB9QoBAKCCAe4wggHqBgkrBgEFBQcwAQEEggHbMIIB1zCBwKEiMCAxHjAcBgNVBAMMFVJlRmluZUlEIE9DU1AgVGVzdCBD"
      + "QRgPMjAyNjA4MDQwNzU5NTRaMGQwYjBNMAkGBSsOAwIaBQAEFG8TmqI0pqWu0NCE1/B/fc+Dv+jtBBQuSpLyyHTWWWb59yJ3"
      + "a/OCz1uzygIUHY+6mluHtmm73OeBXU4tJv6yneaAABgPMjAyNjA4MDQwNzU5NTRaoSMwITAfBgkrBgEFBQcwAQIEEgQQtHFB"
      + "4aFTUF7jaqWFJO0FCjANBgkqhkiG9w0BAQsFAAOCAQEAgOJ8plCKDObCeRZUCD9SkRlNoLBuGKjLzSSQp3dwbl5zhy+W8R0K"
      + "86OkUFk5W0A/+1paL2DVgbuPvByg4DZRf9lOaia3yfDFuuzm2Q+we12Oc5Yzr0kMG3XnE9rddcymh7bzuI7ucWfzqqSVffjS"
      + "WEhRb5sAj6C+Fq4Aq6Zhr0iHsWASoavOCY9wNbEKdOpC13qG4A+C/WnA/4BjyoEFSXlqq/Ioz75yPIPlPF/aRVHb0Aj/0RGT"
      + "egziro9hQOCnYm7oZV5amgk249MimtQlZujP7jNnjVd1cYOK875Hmg74iNUgq7yIfU3JMqwqlyXzs5bMDUIhjCBq+mH0OUJ6"
      + "Ng=="
  )

  /// The nonce OpenSSL put in the request and signed response fixture.
  internal static let nonce = WireHex.data("B47141E1A153505EE36AA58524ED050A")

  /// One second after the generated response's thisUpdate time.
  internal static let currentTime = Date(timeIntervalSince1970: 1_785_830_395)

  /// Seven days, allowed skew, and one second after thisUpdate.
  private static let staleTime = Date(timeIntervalSince1970: 1_786_435_495)

  /// More than the permitted skew after the response's nextUpdate time.
  private static let expiredTime = Date(timeIntervalSince1970: 1_788_422_695)

  @Test
  internal func requestUsesTheRecommendedThirtyTwoByteNonce() {
    #expect(OcspRequest.nonceByteCount == 32)
  }

  @Test
  internal func signedDirectIssuerResponseIsAuthenticated() throws {
    let validity = try Fixture.validate(Self.responseWithNextUpdate)

    #expect(validity.producedAt < Self.currentTime)
    #expect(validity.thisUpdate == validity.producedAt)
    #expect(validity.nextUpdate != nil)
  }

  @Test
  internal func realisticClockSkewDoesNotDiscardFreshEvidence() throws {
    let earlierClock = Self.currentTime.addingTimeInterval(-120)
    let validity = try Fixture.validate(
      Self.responseWithNextUpdate,
      currentTime: earlierClock
    )

    #expect(validity.producedAt > earlierClock)
  }

  @Test
  internal func responseTooFarAheadOfTheLocalClockIsRejected() {
    // currentTime is one second after producedAt, so this is 301 seconds before it.
    let earlierClock = Self.currentTime.addingTimeInterval(-302)

    #expect(throws: OcspResponse.ValidationFailure.responseFromFuture) {
      _ = try Fixture.validate(Self.responseWithNextUpdate, currentTime: earlierClock)
    }
  }

  @Test
  internal func expiredNextUpdateIsRejectedAfterClockSkew() {
    #expect(throws: OcspResponse.ValidationFailure.responseExpired) {
      _ = try Fixture.validate(Self.responseWithNextUpdate, currentTime: Self.expiredTime)
    }
  }

  /// A next-update instant equal to this-update describes no usable validity
  /// interval and must not receive the clock-skew allowance.
  @Test
  internal func zeroLengthResponseValidityIsRejected() {
    let instant = Date(timeIntervalSince1970: 1_000_000)
    let response = OcspResponse.ResponseData(
      nextUpdate: instant,
      producedAt: instant,
      raw: Data(),
      responderId: .keyHash(Data(repeating: 0, count: 20)),
      status: .good,
      thisUpdate: instant
    )

    #expect(throws: OcspResponse.ValidationFailure.responseExpired) {
      try OcspResponse.checkTimes(response, against: instant)
    }
  }

  @Test
  internal func nonceMustMatchWhenTheResponderEchoesIt() {
    #expect(throws: OcspResponse.ValidationFailure.nonceMismatch) {
      _ = try OcspResponse.validate(
        response: Self.responseWithNextUpdate,
        certificate: Self.certificate,
        issuerCertificate: Self.issuerCertificate,
        nonce: Data(repeating: 0, count: Self.nonce.count),
        currentTime: Self.currentTime
      )
    }
  }

  @Test
  internal func signatureTamperingIsRejected() {
    var tampered = Self.responseWithNextUpdate
    tampered[tampered.index(before: tampered.endIndex)] ^= 1

    #expect(throws: OcspResponse.ValidationFailure.signatureInvalid) {
      _ = try Fixture.validate(tampered)
    }
  }

  @Test
  internal func certIdMustNameTheRequestedCertificate() {
    #expect(throws: OcspResponse.ValidationFailure.certificateMismatch) {
      _ = try OcspResponse.validate(
        response: Self.responseWithNextUpdate,
        certificate: Self.issuerCertificate,
        issuerCertificate: Self.issuerCertificate,
        nonce: Self.nonce,
        currentTime: Self.currentTime
      )
    }
  }

  @Test
  internal func noNextUpdateResponseExpiresAfterTheProductFreshnessWindow() {
    #expect(throws: OcspResponse.ValidationFailure.responseExpired) {
      _ = try OcspResponse.validate(
        response: Self.responseWithoutNextUpdate,
        certificate: Self.certificate,
        issuerCertificate: Self.issuerCertificate,
        nonce: Self.nonce,
        currentTime: Self.staleTime
      )
    }
  }

  @Test
  internal func trailingBytesAreNotIgnored() {
    var response = Self.responseWithNextUpdate
    response.append(0)

    #expect(throws: OcspResponse.ValidationFailure.malformed) {
      _ = try Fixture.validate(response)
    }
  }
}
