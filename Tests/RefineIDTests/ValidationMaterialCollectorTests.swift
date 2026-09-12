// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore
@testable import RefineID

/// Direct fail-closed and TSA-chain checks around evidence collection.
@Suite
internal struct ValidationMaterialCollectorTests {
  /// Failures used only to prove that collection did not call a stub.
  private enum StubFailure: Error {
    case unexpectedIo
  }

  /// A self-issued CA certificate used as the card path's root.
  private static let cardRoot = Self.decode(
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

  /// A non-root certificate with no embedded or AIA issuer candidate.
  private static let cardLeaf = Self.decode(
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

  /// A distinct self-issued timestamp signer.
  private static let timestampSigner = Self.decode(
    "MIIBszCCAVigAwIBAgIUMHfE/GmdSvG3+CQRxHSnFzfP2IwwCgYIKoZIzj0EAwIwHDEaMBgGA1UE"
      + "AwwRUmVGaW5lSUQgVGVzdCBUU0EwHhcNMjYwODA0MDc1MzI1WhcNMzYwODAxMDc1MzI1WjAcMRow"
      + "GAYDVQQDDBFSZUZpbmVJRCBUZXN0IFRTQTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABEma/2Y8"
      + "UqzBdNi9vlLoFQ+WHFW8PCTu67N0kmhjl18Eu0kEjTrtF6y5wF1VXf9ktFdnUJX+Rz6FES49kwG7"
      + "cDujeDB2MB0GA1UdDgQWBBTY+L64mtIcQMUST9Jv2XCaRNeLmzAfBgNVHSMEGDAWgBTY+L64mtIc"
      + "QMUST9Jv2XCaRNeLmzAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIGwDAWBgNVHSUBAf8EDDAK"
      + "BggrBgEFBQcDCDAKBggqhkjOPQQDAgNJADBGAiEAwvyfmlibx6Pf8KmrY7VfgYwxbr56A80RBza/"
      + "J4cPYlECIQCYsi5iogIH1DrFGEDBDrUrjaanfMOXp8GithjIM97ohg=="
  )

  /// A deterministic environment that fails any unexpected I/O.
  private static let offline = ValidationMaterialCollector.Dependencies(
    get: { _, _ in throw StubFailure.unexpectedIo },
    post: { _, _, _ in throw StubFailure.unexpectedIo },
    now: { Date(timeIntervalSince1970: 1_785_830_100) },
    random: { _ in throw StubFailure.unexpectedIo }
  )

  /// Base64 fixture text with no forced unwrap.
  private static func decode(_ encoded: String) -> Data {
    Data(base64Encoded: encoded) ?? Data()
  }

  /// Authenticated signer-path revocation retains its document role.
  @Test
  internal func authenticatedSignerRevocationIsClassified() async throws {
    let fixture = try CollectorRevocationFixtures.make()

    do {
      _ = try await ValidationMaterialCollector.collect(
        signerCertificate: fixture.documentSignerCertificate,
        timestampTokens: [],
        dependencies:
          CollectorRevocationFixtures
          .dependencies(for: fixture),
        signerTrustCertificates: [fixture.issuerCertificate]
      )
      Issue.record("Revoked document signer was accepted")
    } catch let failure as ValidationMaterialCollector.Failure {
      #expect(failure == .revoked(.documentSigner))
    } catch {
      Issue.record("Unexpected failure: \(error)")
    }
  }

  /// Authenticated TSA revocation wins before document-signer fallback.
  @Test
  internal func authenticatedTimestampRevocationIsClassifiedFirst()
    async throws
  {
    let fixture = try CollectorRevocationFixtures.make()
    let token = TimestampTokenVerifier.VerifiedToken(
      token: Data("token".utf8),
      signerCertificate: fixture.timestampAuthorityCertificate,
      embeddedCertificates: [
        fixture.timestampAuthorityCertificate,
        fixture.issuerCertificate,
      ],
      verifiedCertificateChain: [
        fixture.timestampAuthorityCertificate,
        fixture.issuerCertificate,
      ],
      trustedCertificate: fixture.issuerCertificate,
      generatedAt: fixture.currentTime
    )

    do {
      _ = try await ValidationMaterialCollector.collect(
        signerCertificate: fixture.documentSignerCertificate,
        timestampTokens: [token],
        dependencies:
          CollectorRevocationFixtures
          .dependencies(for: fixture),
        signerTrustCertificates: [fixture.issuerCertificate]
      )
      Issue.record("Revoked timestamp authority was accepted")
    } catch let failure as ValidationMaterialCollector.Failure {
      #expect(failure == .revoked(.timestampAuthority))
    } catch {
      Issue.record("Unexpected failure: \(error)")
    }
  }

  @Test
  internal func malformedSignerFailsBeforeNetworkIo() async {
    do {
      _ = try await ValidationMaterialCollector.collect(
        signerCertificate: Data("not a certificate".utf8),
        timestampTokens: [],
        dependencies: Self.offline,
        signerTrustCertificates: []
      )
      Issue.record("Malformed signer was accepted")
    } catch let failure as ValidationMaterialCollector.Failure {
      #expect(failure == .certificateMalformed)
    } catch {
      Issue.record("Unexpected failure: \(error)")
    }
  }

  @Test
  internal func missingIssuerFailsInsteadOfWritingPartialEvidence() async {
    do {
      _ = try await ValidationMaterialCollector.collect(
        signerCertificate: Self.cardLeaf,
        timestampTokens: [],
        dependencies: Self.offline,
        signerTrustCertificates: [Self.cardRoot]
      )
      Issue.record("Incomplete certificate path was accepted")
    } catch let failure as ValidationMaterialCollector.Failure {
      #expect(failure == .issuerUnavailable)
    } catch {
      Issue.record("Unexpected failure: \(error)")
    }
  }

  @Test
  internal func verifiedTimestampSignerIsWrittenToTheDssMaterial() async throws {
    let generatedAt = Date(timeIntervalSince1970: 1_785_830_005)
    let token = TimestampTokenVerifier.VerifiedToken(
      token: Data("token".utf8),
      signerCertificate: Self.timestampSigner,
      embeddedCertificates: [Self.timestampSigner],
      verifiedCertificateChain: [Self.timestampSigner],
      trustedCertificate: Self.timestampSigner,
      generatedAt: generatedAt
    )

    let material = try await ValidationMaterialCollector.collect(
      signerCertificate: Self.cardRoot,
      timestampTokens: [token],
      dependencies: Self.offline,
      signerTrustCertificates: [Self.cardRoot]
    )

    #expect(material.certificates == [Self.timestampSigner])
    #expect(material.ocspResponses.isEmpty)
    #expect(material.revocationLists.isEmpty)
  }

  @Test
  internal func selfIssuedNameIsNotAnImplicitTrustAnchor() async {
    do {
      _ = try await ValidationMaterialCollector.collect(
        signerCertificate: Self.cardRoot,
        timestampTokens: [],
        dependencies: Self.offline,
        signerTrustCertificates: []
      )
      Issue.record("An unapproved self-issued certificate ended the path")
    } catch let failure as ValidationMaterialCollector.Failure {
      #expect(failure == .trustAnchorUnavailable)
    } catch {
      Issue.record("Unexpected failure: \(error)")
    }
  }

  @Test
  internal func nonSelfSignedExplicitAnchorNeedsNoParent() async throws {
    let material = try await ValidationMaterialCollector.collect(
      signerCertificate: Self.cardLeaf,
      timestampTokens: [],
      dependencies: Self.offline,
      signerTrustCertificates: [Self.cardLeaf]
    )

    #expect(material.certificates.isEmpty)
    #expect(material.ocspResponses.isEmpty)
    #expect(material.revocationLists.isEmpty)
  }

  @Test
  internal func availableParentsAboveServiceAnchorAreEnriched() async throws {
    let generatedAt = Date(timeIntervalSince1970: 1_785_830_400)
    let token = TimestampTokenVerifier.VerifiedToken(
      token: Data("token".utf8),
      signerCertificate: Self.cardLeaf,
      embeddedCertificates: [Self.cardLeaf, Self.cardRoot],
      verifiedCertificateChain: [Self.cardLeaf],
      trustedCertificate: Self.cardLeaf,
      generatedAt: generatedAt
    )

    let material = try await ValidationMaterialCollector.collect(
      signerCertificate: Self.timestampSigner,
      timestampTokens: [token],
      dependencies: Self.offline,
      signerTrustCertificates: [Self.timestampSigner]
    )

    #expect(material.certificates == [Self.cardLeaf, Self.cardRoot])
  }

  @Test
  internal func unrelatedAnchorCannotTerminateSelfIssuedCertificate() async {
    do {
      _ = try await ValidationMaterialCollector.collect(
        signerCertificate: Self.cardRoot,
        timestampTokens: [],
        dependencies: Self.offline,
        signerTrustCertificates: [Self.timestampSigner]
      )
      Issue.record("An unrelated anchor ended the certificate path")
    } catch let failure as ValidationMaterialCollector.Failure {
      #expect(failure == .issuerUnavailable)
    } catch {
      Issue.record("Unexpected failure: \(error)")
    }
  }

  /// Certificate extensions cannot turn one signing attempt into an
  /// unbounded sequence of network exchanges.
  @Test
  internal func certificateAddressBudgetIsDistinctAndBounded() {
    let addresses = [
      "http://one.example/status",
      "http://one.example/status",
      "http://two.example/status",
      "http://three.example/status",
      "http://four.example/status",
    ]

    let selected = ValidationMaterialCollector.boundedCertificateAddresses(
      addresses
    )

    #expect(
      selected == [
        "http://one.example/status",
        "http://two.example/status",
        "http://three.example/status",
      ]
    )
    #expect(
      selected.count == ValidationMaterialCollector.maximumCertificateAddresses
    )
  }
}
