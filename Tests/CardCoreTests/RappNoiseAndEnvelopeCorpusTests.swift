// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import XCTest

/// Wire version hashed into every prologue (specification Section 6).
internal final class RappNoiseAndEnvelopeCorpusTests: XCTestCase {
  private func checkStaticKeys(
    _ vector: RappNoiseAndEnvelopeCorpusSupport.NoiseVector
  ) throws {
    let initiatorPrivate = try Curve25519.KeyAgreement.PrivateKey(
      rawRepresentation: decodeHex(vector.testOnlyInitiatorStaticPrivateHex)
    )
    let responderPrivate = try Curve25519.KeyAgreement.PrivateKey(
      rawRepresentation: decodeHex(vector.testOnlyResponderStaticPrivateHex)
    )

    XCTAssertEqual(
      encodeHex(initiatorPrivate.publicKey.rawRepresentation),
      vector.initiatorStaticPublicHex,
      vector.name
    )
    XCTAssertEqual(
      encodeHex(responderPrivate.publicKey.rawRepresentation),
      vector.responderStaticPublicHex,
      vector.name
    )
  }

  private func checkPrologue(
    _ vector: RappNoiseAndEnvelopeCorpusSupport.NoiseVector
  ) throws {
    let expectedPrologue: Data
    let expectedMessageLengths: [Int]
    switch vector.name {
    case "pairing-xxpsk3-fixed-transcript":
      expectedPrologue = encodeArray([
        encodeText("RAPP-pairing-v1"),
        encodeArray([
          encodeUnsigned(RappNoiseAndEnvelopeCorpusSupport.wire.major),
          encodeUnsigned(RappNoiseAndEnvelopeCorpusSupport.wire.minor),
          encodeUnsigned(RappNoiseAndEnvelopeCorpusSupport.wire.patch),
        ]),
        encodeText(vector.suite),
        encodeBytes(decodeHex(try XCTUnwrap(vector.offerHashHex))),
        encodeText(vector.transportProfile),
      ])
      expectedMessageLengths = [48, 96, 64]
      XCTAssertEqual(decodeHex(try XCTUnwrap(vector.testOnlyPairingSecretHex)).count, 32)

    case "session-kk-fixed-transcript":
      expectedPrologue = encodeArray([
        encodeText("RAPP-session-v1"),
        encodeArray([
          encodeUnsigned(RappNoiseAndEnvelopeCorpusSupport.wire.major),
          encodeUnsigned(RappNoiseAndEnvelopeCorpusSupport.wire.minor),
          encodeUnsigned(RappNoiseAndEnvelopeCorpusSupport.wire.patch),
        ]),
        encodeText(vector.suite),
        encodeBytes(decodeHex(vector.pairIDHex)),
        encodeBytes(decodeHex(try XCTUnwrap(vector.grantsHashHex))),
        encodeText(vector.transportProfile),
      ])
      expectedMessageLengths = [48, 48]

    default:
      XCTFail("Unknown Noise vector: \(vector.name)")
      return
    }

    XCTAssertEqual(encodeHex(expectedPrologue), vector.prologueHex, vector.name)
    XCTAssertEqual(
      vector.messagesHex.map { decodeHex($0).count }, expectedMessageLengths, vector.name)
    XCTAssertTrue(vector.messagesHex.allSatisfy { !decodeHex($0).isEmpty }, vector.name)
  }

  internal func testFixedNoiseInputsProloguesAndIdentifiers() throws {
    let corpus = try loadCorpus()
    XCTAssertEqual(corpus.noiseHandshake.count, 2)

    for vector in corpus.noiseHandshake {
      try checkStaticKeys(vector)
      try checkPrologue(vector)

      let handshakeHash = decodeHex(vector.handshakeHashHex)
      XCTAssertEqual(handshakeHash.count, 32, vector.name)
      XCTAssertEqual(
        deriveIdentifier(domain: "RAPP-session-id-v1", handshakeHash: handshakeHash),
        vector.sessionIDHex,
        vector.name
      )
      if vector.name.hasPrefix("pairing-") {
        XCTAssertEqual(
          deriveIdentifier(domain: "RAPP-pair-id-v1", handshakeHash: handshakeHash),
          vector.pairIDHex,
          vector.name
        )
        XCTAssertEqual(
          deriveIdentifier(domain: "RAPP-rendezvous-v1", handshakeHash: handshakeHash),
          vector.rendezvousTokenHex,
          vector.name
        )
      }

      XCTAssertEqual(decodeHex(vector.testOnlyInitiatorEphemeralPrivateHex).count, 32)
      XCTAssertEqual(decodeHex(vector.testOnlyResponderEphemeralPrivateHex).count, 32)
    }
  }

  internal func testMalformedEnvelopesMatchIndependentSwiftDecoder() throws {
    let corpus = try loadCorpus()
    XCTAssertEqual(corpus.rejectedEnvelope.count, 12)

    for vector in corpus.rejectedEnvelope {
      let encoded = decodeHex(vector.canonicalCBORHex)
      var decoder = RappNoiseAndEnvelopeCorpusSupport.BoundedCBORDecoder(data: encoded)
      let value = try decoder.decode(depth: 0)
      XCTAssertTrue(decoder.isAtEnd, "Trailing bytes in \(vector.name)")
      XCTAssertEqual(
        RappNoiseAndEnvelopeCorpusSupport.validateEnvelope(
          value,
          supportedCritical: Set(vector.supportedCritical)),
        vector.error,
        vector.name
      )
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
