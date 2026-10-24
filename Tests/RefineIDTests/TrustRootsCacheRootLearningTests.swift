// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// Counts how often the card is asked for a certificate.
  private final class CardReads {
    var calls = 0

    func answer(_ certificate: Data?) -> Data? {
      calls += 1
      return certificate
    }
  }

  extension SharedCertificateCacheTests {
    /// Learning a card's root once and keeping it until it expires.
    @Suite(.serialized)
    internal struct TrustRootsCacheRootLearningTests {
      @Test
      internal func cardRootIsReadOnceThenAnsweredFromThePersistedCache() throws {
        let chain = try CardAuthorityChainFixtures.make()
        let cache = TrustRootsCache()
        defer { cache.reset() }
        let issuerReads = CardReads()
        let rootReads = CardReads()

        let issuer = cache.issuer(
          for: chain.leaf,
          cardIssuer: { issuerReads.answer(chain.issuing) },
          cardRoot: { rootReads.answer(chain.root) })

        #expect(issuer == chain.issuing)
        #expect(issuerReads.calls == 1)
        #expect(rootReads.calls == 1)
        #expect(cache.rootCertificate == chain.root)

        let restarted = TrustRootsCache()
        let again = restarted.issuer(
          for: chain.leaf,
          cardIssuer: { issuerReads.answer(chain.issuing) },
          cardRoot: { rootReads.answer(chain.root) })

        #expect(again == chain.issuing)
        #expect(issuerReads.calls == 1)
        #expect(rootReads.calls == 1)
      }

      @Test
      internal func rootIsNotReadWhenACachedRootIssuedTheIssuingCa() throws {
        let chain = try CardAuthorityChainFixtures.make()
        let cache = TrustRootsCache()
        defer { cache.reset() }
        let seeded = CardReads()
        cache.learnRoot(above: chain.issuing, cardRoot: { seeded.answer(chain.root) })
        let rootReads = CardReads()

        cache.learnRoot(above: chain.issuing, cardRoot: { rootReads.answer(chain.root) })

        #expect(seeded.calls == 1)
        #expect(rootReads.calls == 0)
      }

      @Test
      internal func rootThatDidNotIssueTheIssuingCaIsNotAdmitted() throws {
        let chain = try CardAuthorityChainFixtures.make()
        let cache = TrustRootsCache()
        defer { cache.reset() }
        let rootReads = CardReads()

        cache.learnRoot(above: chain.issuing, cardRoot: { rootReads.answer(chain.impostorRoot) })

        #expect(rootReads.calls == 1)
        #expect(cache.rootCertificate == nil)
        #expect(
          TestCredentialEnvironment.readTrustedCa(
            account: TrustRootsCache.account(for: chain.impostorRoot)) == nil)
      }

      @Test
      internal func expiredRootIsDroppedAndTheCardRootLearnedAgain() throws {
        let chain = try CardAuthorityChainFixtures.make()
        let expiredAccount = TrustRootsCache.account(for: chain.expiredRoot)
        TestCredentialEnvironment.storeTrustedCa(chain.expiredRoot, account: expiredAccount)
        let cache = TrustRootsCache()
        defer { cache.reset() }
        let rootReads = CardReads()

        #expect(TestCredentialEnvironment.readTrustedCa(account: expiredAccount) == nil)
        cache.learnRoot(above: chain.issuing, cardRoot: { rootReads.answer(chain.root) })

        #expect(rootReads.calls == 1)
        #expect(cache.rootCertificate == chain.root)
      }

      @Test
      internal func rootExpiringWhileHeldIsDroppedBeforeTheNextLookup() throws {
        let chain = try CardAuthorityChainFixtures.make()
        let cache = TrustRootsCache()
        defer { cache.reset() }
        cache.registerRoot(chain.expiredRoot)
        let rootReads = CardReads()

        cache.learnRoot(above: chain.issuing, cardRoot: { rootReads.answer(chain.root) })

        #expect(rootReads.calls == 1)
        #expect(cache.rootCertificate == chain.root)
        #expect(!cache.allCertificates.contains(chain.expiredRoot))
      }

      @Test
      internal func unexpiredRootIsKeptAcrossRestarts() throws {
        let chain = try CardAuthorityChainFixtures.make()
        let cache = TrustRootsCache()
        defer { cache.reset() }
        cache.learnRoot(above: chain.issuing, cardRoot: { chain.root })

        let restarted = TrustRootsCache()
        restarted.dropExpired(at: Date())

        #expect(restarted.rootCertificate == chain.root)
      }
    }
  }

#endif
