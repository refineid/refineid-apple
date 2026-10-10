// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP v26.10.9 Noise transcripts on every transport (sections 4.3, 6.2 to 6.4)")
internal struct NoiseSessionCorpusTests {
  /// A fixed plaintext sealed under each split key at counter zero.
  private static let probe = Data("RAPP".utf8)

  private static func vectors(suite: String) throws -> [NoiseVector] {
    try CorpusFile.conformance(filePath: #filePath).noiseHandshake.filter { $0.suite == suite }
  }

  /// The same probe sealed directly with ChaCha20-Poly1305 at nonce zero.
  private static func sealed(underKeyHex keyHex: String) throws -> Data {
    let box = try ChaChaPoly.seal(
      probe, using: SymmetricKey(data: try Data(hex: keyHex)),
      nonce: try ChaChaPoly.Nonce(
        data: Data(count: NoiseSizes.nonceZeroPrefixLength + MemoryLayout<UInt64>.size)))
    return box.ciphertext + box.tag
  }

  /// Both roles of one fixed-ephemeral handshake.
  private static func handshake(
    _ vector: NoiseVector, pattern: NoisePattern, prologue: Data, presharedKey: Data?
  ) throws -> (initiator: NoiseHandshakeState, responder: NoiseHandshakeState) {
    let knowsPeers = presharedKey == nil
    let initiator = try NoiseHandshakeState(
      pattern: pattern, suiteName: vector.suite, prologue: prologue, isInitiator: true,
      localStaticPrivate: try Data(hex: vector.testOnlyInitiatorStaticPrivateHex),
      remoteStaticPublic: knowsPeers ? try Data(hex: vector.responderStaticPublicHex) : nil,
      presharedKey: presharedKey,
      fixedEphemeralPrivate: try Data(hex: vector.testOnlyInitiatorEphemeralPrivateHex))
    let responder = try NoiseHandshakeState(
      pattern: pattern, suiteName: vector.suite, prologue: prologue, isInitiator: false,
      localStaticPrivate: try Data(hex: vector.testOnlyResponderStaticPrivateHex),
      remoteStaticPublic: knowsPeers ? try Data(hex: vector.initiatorStaticPublicHex) : nil,
      presharedKey: presharedKey,
      fixedEphemeralPrivate: try Data(hex: vector.testOnlyResponderEphemeralPrivateHex))
    return (initiator, responder)
  }

  @Test("The corpus covers both suites on both transports")
  internal func coverage() throws {
    let transports: Set = [RappBleGattProfile.name, streamProfile]
    #expect(
      Set(try Self.vectors(suite: RappNoise.sessionSuite).map(\.transportProfile)) == transports)
    #expect(
      Set(try Self.vectors(suite: RappNoise.pairingSuite).map(\.transportProfile)) == transports)
  }

  @Test("Noise_KK reproduces the transcript, hash, split keys and session identifier")
  internal func sessionTranscriptsReplay() throws {
    for vector in try Self.vectors(suite: RappNoise.sessionSuite) {
      let prologue = try RappNoise.sessionPrologue(
        pairIdentifier: try Data(hex: vector.pairIDHex),
        grantsHash: try Data(hex: try #require(vector.grantsHashHex)),
        transportProfile: vector.transportProfile)
      #expect(prologue.hex == vector.prologueHex, "\(vector.name) prologue")
      var (initiator, responder) = try Self.handshake(
        vector, pattern: .knownKnown, prologue: prologue, presharedKey: nil)

      let messageOne = try initiator.writeMessage()
      #expect(messageOne.hex == vector.messagesHex.first, "\(vector.name) message 1")
      #expect(try responder.readMessage(messageOne).isEmpty)
      let messageTwo = try responder.writeMessage()
      #expect(messageTwo.hex == vector.messagesHex.last, "\(vector.name) message 2")
      #expect(try initiator.readMessage(messageTwo).isEmpty)

      #expect(initiator.handshakeHash.hex == vector.handshakeHashHex, "\(vector.name) hash")
      #expect(responder.handshakeHash.hex == vector.handshakeHashHex)
      #expect(
        RappNoise.sessionIdentifier(handshakeHash: initiator.handshakeHash).hex
          == vector.sessionIDHex, "\(vector.name) session_id")

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

  @Test("Noise_XXpsk3 reproduces the pairing transcript and its identifiers")
  internal func pairingTranscriptsReplay() throws {
    for vector in try Self.vectors(suite: RappNoise.pairingSuite) {
      let prologue = try RappNoise.pairingPrologue(
        offerHash: try Data(hex: try #require(vector.offerHashHex)),
        transportProfile: vector.transportProfile)
      #expect(prologue.hex == vector.prologueHex, "\(vector.name) prologue")
      var (initiator, responder) = try Self.handshake(
        vector, pattern: .xxPsk3, prologue: prologue,
        presharedKey: try Data(hex: try #require(vector.testOnlyPairingSecretHex)))

      let messageOne = try initiator.writeMessage()
      #expect(try responder.readMessage(messageOne).isEmpty)
      let messageTwo = try responder.writeMessage()
      #expect(try initiator.readMessage(messageTwo).isEmpty)
      let messageThree = try initiator.writeMessage()
      #expect(try responder.readMessage(messageThree).isEmpty)
      #expect(
        [messageOne, messageTwo, messageThree].map(\.hex) == vector.messagesHex,
        "\(vector.name) messages")

      #expect(initiator.handshakeHash.hex == vector.handshakeHashHex, "\(vector.name) hash")
      #expect(responder.handshakeHash.hex == vector.handshakeHashHex)
      let hash = initiator.handshakeHash
      #expect(RappNoise.pairIdentifier(handshakeHash: hash).hex == vector.pairIDHex)
      #expect(RappNoise.sessionIdentifier(handshakeHash: hash).hex == vector.sessionIDHex)
      #expect(
        RappNoise.rendezvousToken(handshakeHash: hash).hex == vector.rendezvousTokenHex)
    }
  }
}
