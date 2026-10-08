// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP v26.10.1 Noise_KK session transcript (section 6.4)")
internal struct NoiseSessionCorpusTests {
  private static let vectorName = "session-kk-fixed-transcript"
  /// A fixed plaintext sealed under each split key at counter zero.
  private static let probe = Data("RAPP".utf8)

  private static func vector() throws -> NoiseVector {
    let vectors = try CorpusFile.conformance(filePath: #filePath).noiseHandshake
    guard let vector = vectors.first(where: { $0.name == vectorName }) else {
      throw CorpusError.missingHandshake(name: vectorName)
    }
    return vector
  }

  /// The same probe sealed directly with ChaCha20-Poly1305 at nonce zero.
  private static func sealed(underKeyHex keyHex: String) throws -> Data {
    let box = try ChaChaPoly.seal(
      probe, using: SymmetricKey(data: try Data(hex: keyHex)),
      nonce: try ChaChaPoly.Nonce(
        data: Data(count: NoiseSizes.nonceZeroPrefixLength + MemoryLayout<UInt64>.size)))
    return box.ciphertext + box.tag
  }

  @Test("The session suite is the one the specification names")
  internal func suiteName() throws {
    #expect(try Self.vector().suite == RappNoise.sessionSuite)
  }

  @Test("Both roles reproduce the transcript, hash, split keys and session identifier")
  internal func transcriptReplays() throws {
    let vector = try Self.vector()
    let prologue = try RappNoise.sessionPrologue(
      pairIdentifier: try Data(hex: vector.pairIDHex),
      grantsHash: try Data(hex: try #require(vector.grantsHashHex)),
      transportProfile: vector.transportProfile)
    #expect(prologue.hex == vector.prologueHex)

    let initiatorStatic = try Data(hex: vector.testOnlyInitiatorStaticPrivateHex)
    let responderStatic = try Data(hex: vector.testOnlyResponderStaticPrivateHex)
    var initiator = try NoiseHandshakeState(
      pattern: .knownKnown, suiteName: RappNoise.sessionSuite, prologue: prologue,
      isInitiator: true, localStaticPrivate: initiatorStatic,
      remoteStaticPublic: try Data(hex: vector.responderStaticPublicHex), presharedKey: nil,
      fixedEphemeralPrivate: try Data(hex: vector.testOnlyInitiatorEphemeralPrivateHex))
    var responder = try NoiseHandshakeState(
      pattern: .knownKnown, suiteName: RappNoise.sessionSuite, prologue: prologue,
      isInitiator: false, localStaticPrivate: responderStatic,
      remoteStaticPublic: try Data(hex: vector.initiatorStaticPublicHex), presharedKey: nil,
      fixedEphemeralPrivate: try Data(hex: vector.testOnlyResponderEphemeralPrivateHex))

    let messageOne = try initiator.writeMessage()
    #expect(messageOne.hex == vector.messagesHex.first)
    #expect(try responder.readMessage(messageOne).isEmpty)
    let messageTwo = try responder.writeMessage()
    #expect(messageTwo.hex == vector.messagesHex.last)
    #expect(try initiator.readMessage(messageTwo).isEmpty)

    #expect(initiator.handshakeHash.hex == vector.handshakeHashHex)
    #expect(responder.handshakeHash.hex == vector.handshakeHashHex)
    #expect(
      RappNoise.sessionIdentifier(handshakeHash: initiator.handshakeHash).hex
        == vector.sessionIDHex)

    var initiatorSend = try initiator.split().send
    var responderSend = try responder.split().send
    #expect(
      try initiatorSend.encrypt(associatedData: Data(), plaintext: Self.probe)
        == Self.sealed(underKeyHex: try #require(vector.initiatorToResponderKeyHex)))
    #expect(
      try responderSend.encrypt(associatedData: Data(), plaintext: Self.probe)
        == Self.sealed(underKeyHex: try #require(vector.responderToInitiatorKeyHex)))
  }
}
