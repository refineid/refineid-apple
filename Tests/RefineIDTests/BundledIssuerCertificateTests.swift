// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import CryptoKit
  import Foundation
  import Security
  import Testing

  /// Tests for the dynamic in-memory TrustRootsCache and BundledIssuerCertificate fallback.
  @Suite
  internal struct BundledIssuerCertificateTests {
    @Test
    internal func pinnedRootFingerprintsMatchKnownValues() {
      let rsaBytes = TrustRootsCache.pinnedDvvG3RsaSha256
      let eccBytes = TrustRootsCache.pinnedDvvG3EccSha256

      #expect(rsaBytes.count == 32)
      #expect(eccBytes.count == 32)

      #expect(TrustRootsCache.shared.isTrustedRoot(fingerprint: Data(rsaBytes)))
      #expect(TrustRootsCache.shared.isTrustedRoot(fingerprint: Data(eccBytes)))

      let untrusted = Data(repeating: 0x42, count: 32)
      #expect(!TrustRootsCache.shared.isTrustedRoot(fingerprint: untrusted))
    }

    @Test
    internal func dynamicRegistrationAndMatching() throws {
      let cache = TrustRootsCache()

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
      let bundledMatch = BundledIssuerCertificate.der(matching: leaf.certificate)
      #expect(bundledMatch == caSigner.certificate)
    }
  }

#endif
