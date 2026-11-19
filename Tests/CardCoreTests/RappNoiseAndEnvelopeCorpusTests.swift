// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Testing

/// Wire version hashed into every prologue (specification Section 6).
@Suite(.serialized)
internal final class RappNoiseAndEnvelopeCorpusTests {
  /// The malformed envelopes the corpus pins.
  private static let rejectedEnvelopeVectorCount = 10

  private func checkStaticKeys(
    _ vector: RappNoiseAndEnvelopeCorpusSupport.NoiseVector
  ) throws {
    let initiatorPrivate = try Curve25519.KeyAgreement.PrivateKey(
      rawRepresentation: decodeHex(vector.testOnlyInitiatorStaticPrivateHex)
    )
    let responderPrivate = try Curve25519.KeyAgreement.PrivateKey(
      rawRepresentation: decodeHex(vector.testOnlyResponderStaticPrivateHex)
    )

    #expect(
      (encodeHex(initiatorPrivate.publicKey.rawRepresentation))
        == (vector.initiatorStaticPublicHex), "\(vector.name)")
    #expect(
      (encodeHex(responderPrivate.publicKey.rawRepresentation))
        == (vector.responderStaticPublicHex), "\(vector.name)")
  }

  private func checkPrologue(
    _ vector: RappNoiseAndEnvelopeCorpusSupport.NoiseVector
  ) throws {
    let expectedPrologue: Data
    let expectedMessageLengths: [Int]
    switch vector.suite {
    case RappNoiseAndEnvelopeCorpusSupport.pairingSuite:
      expectedPrologue = encodeArray([
        encodeText(RappNoiseAndEnvelopeCorpusSupport.pairingPrologueLabel),
        encodeArray([
          encodeUnsigned(RappNoiseAndEnvelopeCorpusSupport.wire.major),
          encodeUnsigned(RappNoiseAndEnvelopeCorpusSupport.wire.minor),
          encodeUnsigned(RappNoiseAndEnvelopeCorpusSupport.wire.patch),
        ]),
        encodeText(RappNoiseAndEnvelopeCorpusSupport.pairingOfferSuite),
        encodeBytes(decodeHex(try #require(vector.offerHashHex))),
        encodeText(vector.transportProfile),
      ])
      expectedMessageLengths = [48, 96, 64]
      #expect((decodeHex(try #require(vector.testOnlyPairingSecretHex)).count) == (32))

    case RappNoiseAndEnvelopeCorpusSupport.sessionSuite:
      expectedPrologue = encodeArray([
        encodeText(RappNoiseAndEnvelopeCorpusSupport.sessionPrologueLabel),
        encodeArray([
          encodeUnsigned(RappNoiseAndEnvelopeCorpusSupport.wire.major),
          encodeUnsigned(RappNoiseAndEnvelopeCorpusSupport.wire.minor),
          encodeUnsigned(RappNoiseAndEnvelopeCorpusSupport.wire.patch),
        ]),
        encodeText(vector.suite),
        encodeBytes(decodeHex(vector.pairIDHex)),
        encodeBytes(decodeHex(try #require(vector.grantsHashHex))),
        encodeText(vector.transportProfile),
      ])
      expectedMessageLengths = [48, 48]

    default:
      Issue.record("Unknown Noise suite: \(vector.name)")
      return
    }

    #expect((encodeHex(expectedPrologue)) == (vector.prologueHex), "\(vector.name)")
    #expect(
      (vector.messagesHex.map { decodeHex($0).count }) == (expectedMessageLengths), "\(vector.name)"
    )
    #expect((vector.messagesHex.allSatisfy { !decodeHex($0).isEmpty }), "\(vector.name)")
  }

  @Test
  internal func testFixedNoiseInputsProloguesAndIdentifiers() throws {
    let corpus = try loadCorpus()
    #expect((corpus.noiseHandshake.count) == (4))
    #expect(
      (Set(corpus.noiseHandshake.map(\.transportProfile)))
        == (["fi.refineid.rapp.ble", "fi.refineid.stream"]))

    for vector in corpus.noiseHandshake {
      try checkStaticKeys(vector)
      try checkPrologue(vector)

      let handshakeHash = decodeHex(vector.handshakeHashHex)
      #expect((handshakeHash.count) == (64), "\(vector.name)")
      #expect(
        (deriveIdentifier(
          domain: RappNoiseAndEnvelopeCorpusSupport.sessionIdentifierLabel,
          handshakeHash: handshakeHash)) == (vector.sessionIDHex), "\(vector.name)")
      if vector.suite == RappNoiseAndEnvelopeCorpusSupport.pairingSuite {
        #expect(
          (deriveIdentifier(
            domain: RappNoiseAndEnvelopeCorpusSupport.pairIdentifierLabel,
            handshakeHash: handshakeHash)) == (vector.pairIDHex), "\(vector.name)")
      }

      #expect((decodeHex(vector.testOnlyInitiatorEphemeralPrivateHex).count) == (32))
      #expect((decodeHex(vector.testOnlyResponderEphemeralPrivateHex).count) == (32))
    }
  }

  @Test
  internal func testMalformedEnvelopesMatchIndependentSwiftDecoder() throws {
    let corpus = try loadCorpus()
    #expect((corpus.rejectedEnvelope.count) == (Self.rejectedEnvelopeVectorCount))

    for vector in corpus.rejectedEnvelope {
      let encoded = decodeHex(vector.canonicalCBORHex)
      var decoder = RappNoiseAndEnvelopeCorpusSupport.BoundedCBORDecoder(data: encoded)
      let value = try decoder.decode(depth: 0)
      #expect((decoder.isAtEnd), "Trailing bytes in \(vector.name)")
      #expect(
        (RappNoiseAndEnvelopeCorpusSupport.validateEnvelope(value)) == (vector.error),
        "\(vector.name)")
    }
  }

  private func loadCorpus() throws -> RappNoiseAndEnvelopeCorpusSupport.Corpus {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try RappNoiseAndEnvelopeCorpusSupport.corpus(from: repositoryRoot)
  }

  private func deriveIdentifier(domain: String, handshakeHash: Data) -> String {
    RappNoiseAndEnvelopeCorpusSupport.deriveIdentifier(
      domain: domain,
      handshakeHash: handshakeHash)
  }

  private func encodeUnsigned(_ value: UInt64) -> Data {
    RappNoiseAndEnvelopeCorpusSupport.encodeUnsigned(value)
  }

  private func encodeBytes(_ value: Data) -> Data {
    RappNoiseAndEnvelopeCorpusSupport.encodeBytes(value)
  }

  private func encodeText(_ value: String) -> Data {
    RappNoiseAndEnvelopeCorpusSupport.encodeText(value)
  }

  private func encodeArray(_ values: [Data]) -> Data {
    RappNoiseAndEnvelopeCorpusSupport.encodeArray(values)
  }

  private func encodeHex(_ value: Data) -> String {
    RappNoiseAndEnvelopeCorpusSupport.encodeHex(value)
  }

  private func decodeHex(_ value: String) -> Data {
    RappNoiseAndEnvelopeCorpusSupport.decodeHex(value)
  }
}
