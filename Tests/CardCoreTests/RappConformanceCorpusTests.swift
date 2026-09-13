// Copyright 2026 Petri Koistinen <petri.koistinen@iki.fi>
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import CryptoKit
import Foundation
import Testing

@Suite("RAPP independent conformance corpus")
internal struct RappConformanceCorpusTests {
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
        .appendingPathComponent("Documentation/rapp-conformance/rapp-v26.9.13.json")
    )
  }

  // MARK: Functions

  @Test("Corpus identity and provenance are fixed")
  internal func corpusIdentity() throws {
    let source = try Self.corpusSource()
    let digest = Data(SHA256.hash(data: source))
    #expect(
      RappConformanceCorpusSupport.hex(digest)
        == "89df6051b100c2a3fcea3df8f2675ffef67b5bc3b7244b41e8466afd901776fe")

    let corpus = try JSONDecoder().decode(
      RappConformanceCorpusSupport.Corpus.self,
      from: source)
    #expect(corpus.format == "fi.refineid.rapp.conformance-v1")
    #expect(corpus.protocolDocumentVersion == "26.9.13")
    #expect(corpus.deterministicCBOR.count == 15)
    #expect(corpus.identifierDerivation.count == 2)
    #expect(corpus.grantsHash.count == 3)
    #expect(corpus.requestHash.count == 1)
    #expect(corpus.rejectedCBOR.count == 8)
    #expect(corpus.streamRendezvous.count == 5)
  }

  @Test("Swift independently produces every golden deterministic-CBOR value")
  internal func deterministicCBOR() throws {
    for vector in try Self.corpus().deterministicCBOR {
      #expect(
        try RappConformanceCorpusSupport.DeterministicCBOR.encode(vector.value)
          == RappConformanceCorpusSupport.data(fromHex: vector.encodedHex))
    }
  }

  @Test("Swift independently derives pair, session, and rendezvous identifiers")
  internal func identifierDerivation() throws {
    for vector in try Self.corpus().identifierDerivation {
      let handshakeHash = try RappConformanceCorpusSupport.data(fromHex: vector.handshakeHashHex)
      let pairInput = Data("RAPP-pair-id-v1".utf8) + handshakeHash
      let sessionInput = Data("RAPP-session-id-v1".utf8) + handshakeHash
      let rendezvousInput = Data("RAPP-rendezvous-v1".utf8) + handshakeHash
      let pairID = Data(SHA256.hash(data: pairInput).prefix(16))
      let sessionID = Data(SHA256.hash(data: sessionInput).prefix(16))
      let rendezvousToken = Data(SHA256.hash(data: rendezvousInput).prefix(16))
      let expectedPairID = try RappConformanceCorpusSupport.data(fromHex: vector.pairIDHex)
      let expectedSessionID = try RappConformanceCorpusSupport.data(fromHex: vector.sessionIDHex)
      let expectedRendezvousToken = try RappConformanceCorpusSupport.data(
        fromHex: vector.rendezvousTokenHex
      )
      #expect(pairID == expectedPairID)
      #expect(sessionID == expectedSessionID)
      #expect(rendezvousToken == expectedRendezvousToken)
    }
  }

  @Test("Swift independently encodes the accepted stream rendezvous preambles")
  internal func streamRendezvous() throws {
    for vector in try Self.corpus().streamRendezvous {
      let encoded = try RappConformanceCorpusSupport.data(fromHex: vector.encodedHex)
      if vector.accepted {
        let token =
          try vector.rendezvousTokenHex.map(RappConformanceCorpusSupport.data(fromHex:)) ?? Data()
        let preamble = try RappConformanceCorpusSupport.DeterministicCBOR.encode(
          .array([
            .text("RAPP-stream-v1"),
            .text(vector.purpose),
            .bytes(token),
          ])
        )
        #expect(preamble == encoded, "\(vector.name)")
        #expect(vector.error == nil, "\(vector.name)")
      } else {
        #expect(vector.error?.isEmpty == false, "\(vector.name)")
        #expect(!encoded.isEmpty, "\(vector.name)")
      }
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

  @Test("Swift independently constructs and commits a request")
  internal func requestHash() throws {
    for vector in try Self.corpus().requestHash {
      let preimageValue = try RappConformanceCorpusSupport.CorpusValue.array([
        .text("RAPP-request-v1"),
        .bytes(RappConformanceCorpusSupport.data(fromHex: vector.sessionIDHex)),
        .bytes(RappConformanceCorpusSupport.data(fromHex: vector.operationIDHex)),
        .text(vector.profile),
        .text(vector.action),
        vector.context,
        vector.payload,
      ])
      let preimage = try RappConformanceCorpusSupport.DeterministicCBOR.encode(preimageValue)
      let expectedPreimage = try RappConformanceCorpusSupport.data(
        fromHex: vector.preimageCBORHex
      )
      let expectedHash = try RappConformanceCorpusSupport.data(fromHex: vector.sha256Hex)
      #expect(preimage == expectedPreimage)
      #expect(Data(SHA256.hash(data: preimage)) == expectedHash)
    }
  }
}
