// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import Foundation
  import Testing

  @testable import CardCore
  @testable import RefineIDTestHost

  /// A container leaves the signer at XAdES-B-LTA, or a release build
  /// writes nothing; a development build keeps B-LT and says so.
  @Suite
  internal struct AsicSignerArchiveTests {
    /// Why a stand-in authority gave no token.
    private enum Unavailable: Error {
      case authority
    }

    /// One authority shared by the closures that mint its tokens.
    private final class Authority: @unchecked Sendable {
      let identity: DebugTimestampAuthority

      init() throws {
        identity = try DebugTimestampAuthority.make()
      }

      /// A verified token over `digest`, as `TimestampClient` answers.
      func token(over digest: Data) throws -> TimestampTokenVerifier.VerifiedToken {
        let nonce = Data("archive test nonce".utf8)
        let minted = try identity.response(
          imprint: digest, nonce: nonce, generationTime: DebugTimestampAuthority.generationTime)
        let token = try RfcTimestamp.token(
          fromResponse: minted.response, digest: digest, nonceBytes: nonce)
        return try TimestampTokenVerifier.verify(
          token, trustedCertificates: [identity.certificate])
      }
    }

    /// Counts the authority calls: the first is the signature
    /// timestamp, the next the archive timestamp.
    private final class Calls: @unchecked Sendable {
      private let lock = NSLock()
      private var count = 0

      func next() -> Int {
        lock.withLock {
          defer { count += 1 }
          return count
        }
      }
    }

    /// The authority's first call is the signature timestamp.
    private static let signatureTimestampCall = 0

    private static let archiveTimeStampOpen = "<xadesv141:ArchiveTimeStamp "
    private static let certificateValuesOpen = "<xades:CertificateValues "
    private static let developmentLongTermMarker = "-dev-B-LT"

    private static let objects = [
      AsicContainer.DataObject(
        name: "Ledger.txt", mimeType: "text/plain", content: Data("a ledger".utf8))
    ]

    /// The plan, signature and signer certificate the card stage leaves.
    private static func signed() throws -> (plan: XadesSignature.Plan, certificate: Data) {
      let certificate = try SignerCertificateFixtures.makeSigner(for: .ecdsaSha256).certificate
      let plan = try #require(
        XadesSignature.plan(
          objects: Self.objects,
          certificate: certificate,
          profile: .ecdsaP384,
          signedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
      )
      return (plan, certificate)
    }

    /// Stand-in authority and evidence collector.
    ///
    /// The signature timestamp comes from `authority`, the evidence
    /// carries its certificate, and the archive timestamp comes from
    /// `archive`, or fails when it is nil.
    private static func sources(
      authority: Authority,
      archive: Authority?
    ) -> AsicSigner.EvidenceSources {
      let calls = Calls()
      return AsicSigner.EvidenceSources(
        timestamp: { digest in
          guard calls.next() == Self.signatureTimestampCall else {
            guard let archive else { throw Unavailable.authority }
            return try archive.token(over: digest)
          }
          return try authority.token(over: digest)
        },
        collect: { _, _ in
          PdfValidationStore.Material(
            certificates: [authority.identity.certificate],
            ocspResponses: [],
            revocationLists: []
          )
        }
      )
    }

    private static func signatureXml(_ product: AsicSigner.Product) throws -> String {
      let entries = try ZipReader.open(product.bytes).entries
      let xml = try #require(entries[AsicContainer.signatureEntryName])
      return try #require(String(data: xml, encoding: .utf8))
    }

    private static func sign(
      sources: AsicSigner.EvidenceSources,
      policy: SignatureLevelPolicy
    ) async throws -> AsicSigner.Product {
      let signed = try Self.signed()
      return try await AsicSigner.evidenced(
        plan: signed.plan,
        xmlSignature: Data("signature".utf8),
        certificate: signed.certificate,
        objects: Self.objects,
        completion: AsicSigner.Completion(sources: sources, policy: policy)
      )
    }

    @Test
    internal func releaseWritesTheArchiveTimestamp() async throws {
      let authority = try Authority()
      let product = try await Self.sign(
        sources: Self.sources(authority: authority, archive: authority), policy: .longTermOnly)
      let xml = try Self.signatureXml(product)
      #expect(product.belowLongTerm == nil)
      let archive = try #require(xml.range(of: Self.archiveTimeStampOpen))
      let values = try #require(xml.range(of: Self.certificateValuesOpen))
      #expect(values.lowerBound < archive.lowerBound)
    }

    @Test
    internal func releaseRefusesWhenTheArchiveTimestampFails() async throws {
      let authority = try Authority()
      var product: AsicSigner.Product?
      await #expect(throws: DocumentSigner.Failure.self) {
        product = try await Self.sign(
          sources: Self.sources(authority: authority, archive: nil), policy: .longTermOnly)
      }
      #expect(product == nil)
    }

    @Test
    internal func releaseRefusesAnArchiveAuthorityOutsideTheEvidence() async throws {
      let authority = try Authority()
      let stranger = try Authority()
      var product: AsicSigner.Product?
      await #expect(throws: AsicSigner.Failure.self) {
        product = try await Self.sign(
          sources: Self.sources(authority: authority, archive: stranger), policy: .longTermOnly)
      }
      #expect(product == nil)
    }

    @Test
    internal func developmentKeepsLongTermWithoutTheArchiveTimestamp() async throws {
      let authority = try Authority()
      let product = try await Self.sign(
        sources: Self.sources(authority: authority, archive: nil), policy: .highestReached)
      let shortfall = try #require(product.belowLongTerm)
      #expect(
        shortfall
          == BelowLongTermSignature(format: .asice, level: .longTerm, cause: .archiveTimestamp))
      #expect(shortfall.nameMarker == Self.developmentLongTermMarker)
      #expect(shortfall.levelName == "XAdES B-LT")
      #expect(shortfall.notice.contains(Self.developmentLongTermMarker))
      let xml = try Self.signatureXml(product)
      #expect(xml.contains(Self.certificateValuesOpen))
      #expect(!xml.contains(Self.archiveTimeStampOpen))
      let named = SignedDocumentName.suggested(
        sourceNames: Self.objects.map(\.name),
        format: .asice,
        at: product.signatureTimestampTime,
        marker: SignedDocument(product).nameMarker
      )
      #expect(named.hasSuffix(Self.developmentLongTermMarker + ".asice"))
    }
  }

#endif
