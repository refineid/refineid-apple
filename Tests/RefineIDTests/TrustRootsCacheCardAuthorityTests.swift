// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// The signing session's own trust-anchor caching.
  ///
  /// A card-supplied issuing certificate becomes the explicit anchor
  /// the evidence walk requires; a warm cache answers without asking
  /// the card again.
  @Suite(.serialized)
  internal struct TrustRootsCacheCardAuthorityTests {
    @Test
    internal func cardSuppliedIssuerResolvesAnAnchorlessLeaf() throws {
      let cache = TrustRootsCache()
      defer { cache.reset() }
      let authority = try SignerCertificateFixtures.makeSigner(
        for: .rsaSha256,
        certificateProfile: .certificateAuthority
      )
      let authorityFacts = try #require(
        CertificateFacts(der: authority.certificate)
      )
      let leaf = try SignerCertificateFixtures.makeSigner(
        for: .rsaSha256,
        issuerName: authorityFacts.subjectName
      )

      #expect(cache.der(matching: leaf.certificate) == nil)

      // One authority doubles as the root here: every generated
      // signer shares one fixed subject, so a second authority
      // would overwrite the first in the subject index.
      let anchor = cache.ensureIssuer(
        for: leaf.certificate,
        cardIssuer: authority.certificate,
        cardRoot: authority.certificate
      )

      #expect(anchor == authority.certificate)
      #expect(cache.der(matching: leaf.certificate) == authority.certificate)
      #expect(cache.rootCertificate == authority.certificate)
    }

    @Test
    internal func warmCacheAnswersWithoutCardAuthorities() throws {
      let cache = TrustRootsCache()
      defer { cache.reset() }
      let authority = try SignerCertificateFixtures.makeSigner(
        for: .rsaSha256,
        certificateProfile: .certificateAuthority
      )
      let authorityFacts = try #require(
        CertificateFacts(der: authority.certificate)
      )
      let leaf = try SignerCertificateFixtures.makeSigner(
        for: .rsaSha256,
        issuerName: authorityFacts.subjectName
      )
      cache.register(authority.certificate)

      let anchor = cache.ensureIssuer(
        for: leaf.certificate,
        cardIssuer: nil,
        cardRoot: nil
      )

      #expect(anchor == authority.certificate)
      #expect(cache.rootCertificate == nil)
    }

    @Test
    internal func persistedCaSurvivesAcrossCacheInstances() throws {
      let cache1 = TrustRootsCache()
      defer { cache1.reset() }

      let authority = try SignerCertificateFixtures.makeSigner(
        for: .rsaSha256,
        certificateProfile: .certificateAuthority
      )
      let authorityFacts = try #require(
        CertificateFacts(der: authority.certificate)
      )
      let leaf = try SignerCertificateFixtures.makeSigner(
        for: .rsaSha256,
        issuerName: authorityFacts.subjectName
      )
      cache1.register(authority.certificate)
      #expect(cache1.der(matching: leaf.certificate) == authority.certificate)

      let cache2 = TrustRootsCache()
      #expect(cache2.der(matching: leaf.certificate) == authority.certificate)
    }

    @Test
    internal func expiredCaIsPrunedOnStartup() throws {
      let cache = TrustRootsCache()
      defer { cache.reset() }

      let expiredAuthority = try SignerCertificateFixtures.makeSigner(
        for: .rsaSha256,
        certificateProfile: .expiredBeforeIssue
      )
      TestCredentialEnvironment.storeTrustedCa(
        expiredAuthority.certificate,
        account: "expired-authority"
      )

      let reloaded = TrustRootsCache()
      #expect(TestCredentialEnvironment.readTrustedCa(account: "expired-authority") == nil)
      #expect(reloaded.der(matching: expiredAuthority.certificate) == nil)
    }
  }

#endif
