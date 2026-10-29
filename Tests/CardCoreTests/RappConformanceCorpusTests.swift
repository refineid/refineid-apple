// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Testing

@Suite("RAPP independent conformance corpus")
internal struct RappConformanceCorpusTests {
  // MARK: Static Properties

  /// The pinned corpus file, and the SHA-256 digest of its bytes.
  private static let corpusPath = "Documentation/rapp-conformance/rapp-v26.10.29.json"
  private static let corpusDigest =
    "e37f9c744daf81705445dfdf349ed4f5d29cff2fe77919adf0d099da2a1ec44c"

  // MARK: Static Functions

  private static func corpus() throws -> RappConformanceCorpusSupport.Corpus {
    try JSONDecoder().decode(RappConformanceCorpusSupport.Corpus.self, from: corpusSource())
  }

  private static func corpusSource() throws -> Data {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try Data(
      contentsOf:
        repositoryRoot
        .appendingPathComponent(corpusPath)
    )
  }

  // MARK: Functions

  @Test("Corpus identity and provenance are fixed")
  internal func corpusIdentity() throws {
    let source = try Self.corpusSource()
    let digest = Data(SHA256.hash(data: source))
    #expect(RappConformanceCorpusSupport.hex(digest) == Self.corpusDigest)

    let corpus = try JSONDecoder().decode(
      RappConformanceCorpusSupport.Corpus.self,
      from: source)
    #expect(corpus.format == "fi.refineid.rapp.conformance")
    #expect(corpus.protocolDocumentVersion == "26.10.29")
    #expect(corpus.deterministicCBOR.count == 15)
    #expect(corpus.identifierDerivation.count == 2)
    #expect(corpus.grantsHash.count == 3)
    #expect(corpus.rejectedCBOR.count == 8)
  }

  @Test("Swift independently produces every golden deterministic-CBOR value")
  internal func deterministicCBOR() throws {
    for vector in try Self.corpus().deterministicCBOR {
      #expect(
        try RappConformanceCorpusSupport.DeterministicCBOR.encode(vector.value)
          == RappConformanceCorpusSupport.data(fromHex: vector.encodedHex))
    }
  }

  @Test("Swift independently derives pair and session identifiers")
  internal func identifierDerivation() throws {
    for vector in try Self.corpus().identifierDerivation {
      let handshakeHash = try RappConformanceCorpusSupport.data(fromHex: vector.handshakeHashHex)
      let pairInput =
        Data(RappNoiseAndEnvelopeCorpusSupport.pairIdentifierLabel.utf8) + handshakeHash
      let sessionInput =
        Data(RappNoiseAndEnvelopeCorpusSupport.sessionIdentifierLabel.utf8) + handshakeHash
      let identifierLength = RappNoiseAndEnvelopeCorpusSupport.Constants.hashPrefixLength
      let pairID = Data(SHA512.hash(data: pairInput).prefix(identifierLength))
      let sessionID = Data(SHA512.hash(data: sessionInput).prefix(identifierLength))
      let expectedPairID = try RappConformanceCorpusSupport.data(fromHex: vector.pairIDHex)
      let expectedSessionID = try RappConformanceCorpusSupport.data(fromHex: vector.sessionIDHex)
      #expect(pairID == expectedPairID)
      #expect(sessionID == expectedSessionID)
    }
  }

  @Test("Swift independently normalizes and commits granted profiles")
  internal func grantsHash() throws {
    for vector in try Self.corpus().grantsHash {
      let profiles = vector.profiles.sorted { left, right in
        Data(left.utf8).lexicographicallyPrecedes(Data(right.utf8))
      }
      let preimage = try RappConformanceCorpusSupport.DeterministicCBOR.encode(
        .array(profiles.map(RappConformanceCorpusSupport.CorpusValue.text))
      )
      let expectedPreimage = try RappConformanceCorpusSupport.data(
        fromHex: vector.canonicalCBORHex
      )
      let expectedHash = try RappConformanceCorpusSupport.data(fromHex: vector.sha256Hex)
      #expect(preimage == expectedPreimage)
      #expect(Data(SHA256.hash(data: preimage)) == expectedHash)
    }
  }
}
