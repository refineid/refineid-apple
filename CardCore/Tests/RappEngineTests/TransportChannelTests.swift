// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
//
// Replays the post-handshake frames emitted by the reference engine, so the
// Swift channel is proven past the handshake, where the conformance corpus
// alone does not reach.

import CryptoKit
import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP transport channel against the vendored frames")
internal struct TransportChannelTests {
  private struct Channels {
    var initiator: RappSecureChannel
    var responder: RappSecureChannel
    let handshakeHash: Data
  }

  /// Eight frames per direction, so a counter reaches well past its first
  /// value and an endianness mistake cannot hide.
  private static let minimumFramesPerSuite = 16

  private static func publicKey(from privateKey: Data) throws -> Data {
    try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
      .publicKey.rawRepresentation
  }

  /// Rebuild the handshake from the fixed keys, then take its two directions.
  private static func establish(suite: TransportSuite, keys: NoiseVector) throws -> Channels {
    let prologue = try Data(hex: suite.prologueHex)
    let initiatorStatic = try Data(hex: keys.testOnlyInitiatorStaticPrivateHex)
    let responderStatic = try Data(hex: keys.testOnlyResponderStaticPrivateHex)
    let isPairing = suite.suite.contains("XXpsk3") || suite.name.contains("pairing")
    let secret = isPairing ? try Data(hex: keys.testOnlyPairingSecretHex ?? "") : nil

    var initiator = try NoiseHandshakeState(
      pattern: isPairing ? .xxPsk3 : .knownKnown, suiteName: suite.suite, prologue: prologue,
      isInitiator: true, localStaticPrivate: initiatorStatic,
      remoteStaticPublic: isPairing ? nil : try publicKey(from: responderStatic),
      presharedKey: secret,
      fixedEphemeralPrivate: try Data(hex: keys.testOnlyInitiatorEphemeralPrivateHex))
    var responder = try NoiseHandshakeState(
      pattern: isPairing ? .xxPsk3 : .knownKnown, suiteName: suite.suite, prologue: prologue,
      isInitiator: false, localStaticPrivate: responderStatic,
      remoteStaticPublic: isPairing ? nil : try publicKey(from: initiatorStatic),
      presharedKey: secret,
      fixedEphemeralPrivate: try Data(hex: keys.testOnlyResponderEphemeralPrivateHex))

    for index in keys.messagesHex.indices {
      if index.isMultiple(of: 2) {
        _ = try responder.readMessage(try initiator.writeMessage())
      } else {
        _ = try initiator.readMessage(try responder.writeMessage())
      }
    }

    let initiatorSplit = try initiator.split()
    let responderSplit = try responder.split()
    return Channels(
      initiator: RappSecureChannel(
        send: initiatorSplit.send, receive: initiatorSplit.receive),
      responder: RappSecureChannel(
        send: responderSplit.send, receive: responderSplit.receive),
      handshakeHash: initiator.handshakeHash)
  }

  /// A fresh pair sharing one key, so counters line up and each control fails
  /// for the reason it is testing.
  private static func matchedPair() -> (writer: RappSecureChannel, reader: RappSecureChannel) {
    let material = Data(repeating: 0x2B, count: NoiseSizes.keyLength)
    var send = NoiseCipherState()
    var receive = NoiseCipherState()
    send.initializeKey(material)
    receive.initializeKey(material)
    return (
      RappSecureChannel(send: send, receive: receive),
      RappSecureChannel(send: send, receive: receive)
    )
  }
  @Test("The vendored frames describe both suites and both directions")
  internal func vectorIdentity() throws {
    let vectors = try CorpusFile.transport(filePath: #filePath)
    #expect(vectors.format == "fi.refineid.rapp.transport-vectors-v1")
    #expect(vectors.maxFrameSize == RappFrameLimits.maximumFrame)
    #expect(vectors.maxFramePlaintext == RappFrameLimits.maximumPlaintext)
    #expect(vectors.suites.count == 2)
    for suite in vectors.suites {
      let directions = Set(suite.frames.map(\.direction))
      #expect(directions.count == 2, "\(suite.name)")
      #expect(suite.frames.count >= Self.minimumFramesPerSuite, "\(suite.name)")
    }
  }

  @Test("Every sealed frame matches the reference engine byte for byte")
  internal func sealedFramesMatch() throws {
    let handshakes = try CorpusFile.conformance(filePath: #filePath).noiseHandshake
    for suite in try CorpusFile.transport(filePath: #filePath).suites {
      guard let keys = handshakes.first(where: { $0.name == suite.name }) else {
        throw CorpusError.missingHandshake(name: suite.name)
      }
      var channels = try Self.establish(suite: suite, keys: keys)
      #expect(channels.handshakeHash.hex == suite.handshakeHashHex, "\(suite.name)")

      for frame in suite.frames {
        let plaintext = try Data(hex: frame.plaintextHex)
        let toResponder = frame.direction == TransportFrame.initiatorToResponder
        let sealed =
          toResponder
          ? try channels.initiator.seal(plaintext) : try channels.responder.seal(plaintext)
        #expect(sealed.hex == frame.ciphertextHex, "\(suite.name) counter \(frame.counter)")

        let opened =
          toResponder
          ? try channels.responder.open(sealed) : try channels.initiator.open(sealed)
        #expect(opened == plaintext, "\(suite.name) counter \(frame.counter)")
      }
    }
  }

  @Test("A matched pair carries one frame")
  internal func matchedPairCarriesAFrame() throws {
    var pair = Self.matchedPair()
    let payload = Data("payload".utf8)
    #expect(try pair.reader.open(try pair.writer.seal(payload)) == payload)
  }

  @Test("A tampered frame is an unattributable integrity failure")
  internal func tamperedFrameIsUnattributable() throws {
    var pair = Self.matchedPair()
    var frame = try pair.writer.seal(Data("carrier".utf8))
    let first = try #require(frame.indices.first)
    frame[first] ^= 1
    #expect(throws: RappOpenFailure.sessionIntegrityFailure) {
      _ = try pair.reader.open(frame)
    }
  }

  @Test("Decrypted but nonconforming plaintext is an authenticated violation")
  internal func nonconformingPlaintextIsAViolation() throws {
    var pair = Self.matchedPair()
    let frame = try pair.writer.seal(Data("payload".utf8))
    #expect(throws: RappOpenFailure.authenticatedProtocolViolation) {
      _ = try pair.reader.open(frame) { _ in throw WireError.unknownMessageType }
    }
  }

  @Test("A plaintext above the frame limit is refused")
  internal func oversizedPlaintextIsRefused() throws {
    var pair = Self.matchedPair()
    let oversized = Data(repeating: 0, count: RappFrameLimits.maximumPlaintext + 1)
    #expect(throws: RappFrameError.self) { _ = try pair.writer.seal(oversized) }
  }

  @Test("A frame above the wire limit is refused before any key is used")
  internal func oversizedFrameIsRefused() throws {
    var pair = Self.matchedPair()
    let oversized = Data(repeating: 0, count: RappFrameLimits.maximumFrame + 1)
    #expect(throws: RappFrameError.self) { _ = try pair.reader.open(oversized) }
  }
}
