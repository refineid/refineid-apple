// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import CryptoKit
  import Foundation
  import Security
  import Testing

  /// Tests for the dynamic in-memory TrustRootsCache and IssuerCertificate fallback.
  @Suite(.serialized)
  internal struct IssuerCertificateTests {
    @Test
    internal func trustedRootMatchesRegisteredCertificates() throws {
      let cache = TrustRootsCache()
      defer { cache.reset() }

      let rootSigner = try SignerCertificateFixtures.makeSigner(
        for: .rsaSha256,
        certificateProfile: .certificateAuthority
      )
      let rootFp = Data(SHA256.hash(data: rootSigner.certificate))

      let untrusted = Data(repeating: 0x42, count: 32)
      #expect(!cache.isTrustedRoot(fingerprint: untrusted))
      #expect(!cache.isTrustedRoot(fingerprint: rootFp))

      cache.registerRoot(rootSigner.certificate)
      #expect(cache.isTrustedRoot(fingerprint: rootFp))
    }

    @Test
    internal func dynamicRegistrationAndMatching() throws {
      let cache = TrustRootsCache()
      defer { cache.reset() }

      let caSigner = try SignerCertificateFixtures.makeSigner(
        for: .rsaSha256,
        certificateProfile: .certificateAuthority
      )
      let caFacts = try #require(CertificateFacts(der: caSigner.certificate))

      let leaf = try SignerCertificateFixtures.makeSigner(
        for: .rsaSha256,
        issuerName: caFacts.subjectName
      )

      #expect(cache.der(matching: leaf.certificate) == nil)

      cache.register(caSigner.certificate)
      #expect(cache.intermediateCertificate == caSigner.certificate)

      let matched = try #require(cache.der(matching: leaf.certificate))
      #expect(matched == caSigner.certificate)

      let rootSigner = try SignerCertificateFixtures.makeSigner(
        for: .rsaSha256,
        certificateProfile: .certificateAuthority
      )
      cache.registerRoot(rootSigner.certificate)
      #expect(cache.rootCertificate == rootSigner.certificate)

      let rootFp = Data(SHA256.hash(data: rootSigner.certificate))
      #expect(cache.containsFingerprint(rootFp))
      #expect(cache.isTrustedRoot(fingerprint: rootFp))

      TrustRootsCache.shared.register(caSigner.certificate)
      defer { TrustRootsCache.shared.reset() }
      let issuerMatch = IssuerCertificate.der(matching: leaf.certificate)
      #expect(issuerMatch == caSigner.certificate)
    }
  }

#endif
