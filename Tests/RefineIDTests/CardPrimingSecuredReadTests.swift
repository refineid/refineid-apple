// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore
  @testable import RefineIDTestHost

  extension SharedCertificateCacheTests {
    /// The card reads of a first setup, counted on a card that answers
    /// from its files.
    @Suite(.serialized)
    internal struct CardPrimingSecuredReadTests {
      /// A synthetic current-card serial: letters, nine printed characters.
      private static let chipSerial = "XA1234567"

      /// TokenInfo version.
      private static let tokenInfoVersion = 0

      /// A card carrying every certificate setup could read.
      private static func card(
        _ chain: CardAuthorityChainFixtures.Chain
      ) -> FileSystemCardChannel {
        FileSystemCardChannel(files: [
          (.authCertificate, chain.leaf),
          (.signatureCertificate, chain.leaf),
          (.secondSignatureCertificate, chain.leaf),
          (.issuingCertificate, chain.issuing),
          (.rootCertificate, chain.root),
          (
            .tokenInfo,
            DerEncoder.sequence([
              DerEncoder.integer(Self.tokenInfoVersion),
              DerEncoder.octetString(Data(Self.chipSerial.utf8)),
            ])
          ),
        ])
      }

      /// Runs the secured reads and records the files read before the store.
      private static func prime(
        _ card: FileSystemCardChannel
      ) throws -> (payload: CardPriming.Payload, readBeforeStore: [UInt16]) {
        var readBeforeStore: [UInt16] = []
        let payload = try CardPriming.readSecuredPayload(
          operations: CardOperations(channel: card),
          sheet: NearFieldSheet(.setup) { _ in
            // The sheet's text is not under test.
          },
          store: { _ in readBeforeStore = card.filesRead })
        return (payload, readBeforeStore)
      }

      @Test
      internal func setupReadsNoQualifiedCertificate() throws {
        TrustRootsCache.shared.reset()
        defer { TrustRootsCache.shared.reset() }
        let card = Self.card(try CardAuthorityChainFixtures.make())

        _ = try Self.prime(card)

        #expect(!card.filesRead.contains(FileIdentifier.signatureCertificate.value))
        #expect(!card.filesRead.contains(FileIdentifier.secondSignatureCertificate.value))
      }

      @Test
      internal func identityIsStoredBeforeTheCountersAndRootAreRead() throws {
        TrustRootsCache.shared.reset()
        defer { TrustRootsCache.shared.reset() }
        let chain = try CardAuthorityChainFixtures.make()
        let card = Self.card(chain)

        let (payload, readBeforeStore) = try Self.prime(card)

        #expect(payload.identity.certificate == chain.leaf)
        #expect(payload.identity.issuer == chain.issuing)
        #expect(
          readBeforeStore == [
            FileIdentifier.authCertificate.value,
            FileIdentifier.tokenInfo.value,
            FileIdentifier.issuingCertificate.value,
          ])
        #expect(card.filesRead == readBeforeStore + [FileIdentifier.rootCertificate.value])
      }

      @Test
      internal func cachedAuthoritiesLeaveOnlyTheCardsOwnFilesToRead() throws {
        TrustRootsCache.shared.reset()
        defer { TrustRootsCache.shared.reset() }
        let chain = try CardAuthorityChainFixtures.make()
        _ = try Self.prime(Self.card(chain))
        let card = Self.card(chain)

        _ = try Self.prime(card)

        #expect(
          card.filesRead == [
            FileIdentifier.authCertificate.value,
            FileIdentifier.tokenInfo.value,
          ])
      }

      @Test
      internal func signingReadsTheQualifiedCertificateOnlyWhenNoneIsCached() throws {
        let chain = try CardAuthorityChainFixtures.make()
        let card = Self.card(chain)
        let operations = CardOperations(channel: card)

        let read = CardMaintenance.qualifiedCertificate(cached: nil, operations: operations)
        let cached = CardMaintenance.qualifiedCertificate(cached: read, operations: operations)

        #expect(read == chain.leaf)
        #expect(cached == chain.leaf)
        #expect(card.filesRead == [FileIdentifier.signatureCertificate.value])
      }
    }
  }

#endif
