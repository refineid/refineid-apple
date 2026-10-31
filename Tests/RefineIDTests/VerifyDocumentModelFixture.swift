// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import CardCore
@testable import RefineIDTestHost

/// A deterministic RFC 6960 test CA, a leaf it issued, and a good
/// answer it signed for that leaf, with a report built over them.
internal enum VerifyDocumentModelFixture {
  /// An RSA CA certificate used only for deterministic test material.
  internal static let issuerCertificate = Self.data(
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
  internal static let certificate = Self.data(
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

  /// A direct-issuer good answer for `certificate`.
  internal static let goodResponse = Self.data(
    "MIICCAoBAKCCAgEwggH9BgkrBgEFBQcwAQEEggHuMIIB6jCB06EiMCAxHjAcBgNVBAMMFVJlRmluZUlEIE9DU1AgVGVzdCBD"
      + "QRgPMjAyNjA4MDQwNzU5NTRaMHcwdTBNMAkGBSsOAwIaBQAEFG8TmqI0pqWu0NCE1/B/fc+Dv+jtBBQuSpLyyHTWWWb59yJ3"
      + "a/OCz1uzygIUHY+6mluHtmm73OeBXU4tJv6yneaAABgPMjAyNjA4MDQwNzU5NTRaoBEYDzIwMjYwOTAzMDc1OTU0WqEjMCEw"
      + "HwYJKwYBBQUHMAECBBIEELRxQeGhU1Be42qlhSTtBQowDQYJKoZIhvcNAQELBQADggEBAHbw7l29FG+XvoQE2hw3VHv1n5WJ"
      + "aw7tc5aBr31B7j2oEBUqqzp+e4FszwCfE6O7UavXVRRzx6p9BK1if/QXw8sTnMTmNOJqVYYOcDa2WDMRple+6gO3bkibPBwW"
      + "xHWaj+OVmbE2Kqyw36e7+ily0Uy2C7eXVEGnf3dGBMUvZiXMMxB850oPkD65vHZ8UIiN6Ha72b69mYwcSIz0MVvoqir3jf3e"
      + "/bODrfWy+iW7tQ1sJ2n+qPZXTjurJ4RMpA3Awx+D1OdXz5FPzDm3exmwnvtZGCA2sWu/nzTEOX7/57FZVTdYB7AMsGnw5D2u"
      + "j2QSZJKqjs/kePWoNcT1zRoAZGE="
  )

  /// One second after the answer's thisUpdate.
  internal static let currentTime =
    ISO8601DateFormatter().date(from: "2026-08-04T07:59:55Z") ?? Date.distantPast

  /// A judged report whose anchored path leaves the leaf's status
  /// unavailable.
  internal static var report: DocumentVerification.SignatureReport {
    DocumentVerification.SignatureReport(
      signerCommonName: "",
      signerIdentifier: "",
      signerCertificate: Self.certificate,
      documentIntact: true,
      signatureValid: true,
      chain: .anchored(path: [Self.certificate, Self.issuerCertificate]),
      timestamps: [],
      validationTime: .currentClock(Self.currentTime),
      revocationLinks: [
        RevocationJudge.Link(
          certificate: Self.certificate, issuer: Self.issuerCertificate, state: .unavailable)
      ],
      coversWholeDocument: true
    )
  }

  /// A document report with that one signature.
  internal static var documentReport: DocumentVerification.DocumentReport {
    DocumentVerification.DocumentReport(signatures: [.judged(Self.report)], documentTimestamps: [])
  }

  /// Decodes one invariant base64 fixture.
  private static func data(_ encoded: String) -> Data {
    Data(base64Encoded: encoded) ?? Data()
  }
}
