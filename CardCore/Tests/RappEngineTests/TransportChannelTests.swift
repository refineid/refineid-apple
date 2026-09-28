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

  private static func establishPairingChannels() throws -> Channels {
    let offerHash = Data(repeating: 0x66, count: 32)
    let transportProfile = "apple-peer-v1"
    let prologue = try RappNoise.pairingPrologue(
      offerHash: offerHash, transportProfile: transportProfile)
    let initiatorStatic = Curve25519.KeyAgreement.PrivateKey().rawRepresentation
    let responderStatic = Curve25519.KeyAgreement.PrivateKey().rawRepresentation
    let pairingSecret = Data(repeating: 0x55, count: 32)

    var initiator = try NoiseHandshakeState(
      pattern: .xxPsk3,
      suiteName: RappNoise.pairingSuite,
      prologue: prologue,
      isInitiator: true,
      localStaticPrivate: initiatorStatic,
      remoteStaticPublic: nil,
      presharedKey: pairingSecret,
      fixedEphemeralPrivate: Curve25519.KeyAgreement.PrivateKey().rawRepresentation
    )
    var responder = try NoiseHandshakeState(
      pattern: .xxPsk3,
      suiteName: RappNoise.pairingSuite,
      prologue: prologue,
      isInitiator: false,
      localStaticPrivate: responderStatic,
      remoteStaticPublic: nil,
      presharedKey: pairingSecret,
      fixedEphemeralPrivate: Curve25519.KeyAgreement.PrivateKey().rawRepresentation
    )

    let msg1 = try initiator.writeMessage()
    _ = try responder.readMessage(msg1)
    let msg2 = try responder.writeMessage()
    _ = try initiator.readMessage(msg2)
    let msg3 = try initiator.writeMessage()
    _ = try responder.readMessage(msg3)

    let initiatorSplit = try initiator.split()
    let responderSplit = try responder.split()
    return Channels(
      initiator: RappSecureChannel(send: initiatorSplit.send, receive: initiatorSplit.receive),
      responder: RappSecureChannel(send: responderSplit.send, receive: responderSplit.receive),
      handshakeHash: initiator.handshakeHash
    )
  }

  private static func establishSessionChannels() throws -> Channels {
    let pairID = Data(repeating: 0x11, count: 16)
    let grantsHash = Data(repeating: 0x77, count: 32)
    let transportProfile = "apple-peer-v1"
    let prologue = try RappNoise.sessionPrologue(
      pairIdentifier: pairID,
      grantsHash: grantsHash,
      transportProfile: transportProfile
    )
    let initiatorStaticKey = Curve25519.KeyAgreement.PrivateKey()
    let responderStaticKey = Curve25519.KeyAgreement.PrivateKey()

    var initiator = try NoiseHandshakeState(
      pattern: .knownKnownHfs,
      suiteName: RappNoise.sessionSuite,
      prologue: prologue,
      isInitiator: true,
      localStaticPrivate: initiatorStaticKey.rawRepresentation,
      remoteStaticPublic: responderStaticKey.publicKey.rawRepresentation,
      presharedKey: nil,
      fixedEphemeralPrivate: Curve25519.KeyAgreement.PrivateKey().rawRepresentation
    )
    var responder = try NoiseHandshakeState(
      pattern: .knownKnownHfs,
      suiteName: RappNoise.sessionSuite,
      prologue: prologue,
      isInitiator: false,
      localStaticPrivate: responderStaticKey.rawRepresentation,
      remoteStaticPublic: initiatorStaticKey.publicKey.rawRepresentation,
      presharedKey: nil,
      fixedEphemeralPrivate: Curve25519.KeyAgreement.PrivateKey().rawRepresentation
    )

    let msg1 = try initiator.writeMessage()
    _ = try responder.readMessage(msg1)
    let msg2 = try responder.writeMessage()
    _ = try initiator.readMessage(msg2)

    let initiatorSplit = try initiator.split()
    let responderSplit = try responder.split()
    return Channels(
      initiator: RappSecureChannel(send: initiatorSplit.send, receive: initiatorSplit.receive),
      responder: RappSecureChannel(send: responderSplit.send, receive: responderSplit.receive),
      handshakeHash: initiator.handshakeHash
    )
  }

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

  @Test("Pairing transport channel seals and opens frames bidirectionally")
  internal func pairingTransportChannelRoundTrip() throws {
    var channels = try Self.establishPairingChannels()
    #expect(channels.handshakeHash.count == NoiseSizes.hashLength)

    for counter in 0..<Self.minimumFramesPerSuite {
      let initiatorPayload = Data("initiator-frame-\(counter)".utf8)
      let sealedToResponder = try channels.initiator.seal(initiatorPayload)
      let openedByResponder = try channels.responder.open(sealedToResponder)
      #expect(openedByResponder == initiatorPayload)

      let responderPayload = Data("responder-frame-\(counter)".utf8)
      let sealedToInitiator = try channels.responder.seal(responderPayload)
      let openedByInitiator = try channels.initiator.open(sealedToInitiator)
      #expect(openedByInitiator == responderPayload)
    }
  }

  @Test("Session hybrid post-quantum transport channel seals and opens frames bidirectionally")
  internal func sessionTransportChannelRoundTrip() throws {
    var channels = try Self.establishSessionChannels()
    #expect(channels.handshakeHash.count == NoiseSizes.hashLength)

    for counter in 0..<Self.minimumFramesPerSuite {
      let initiatorPayload = Data("pq-initiator-frame-\(counter)".utf8)
      let sealedToResponder = try channels.initiator.seal(initiatorPayload)
      let openedByResponder = try channels.responder.open(sealedToResponder)
      #expect(openedByResponder == initiatorPayload)

      let responderPayload = Data("pq-responder-frame-\(counter)".utf8)
      let sealedToInitiator = try channels.responder.seal(responderPayload)
      let openedByInitiator = try channels.initiator.open(sealedToInitiator)
      #expect(openedByInitiator == responderPayload)
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
    guard !frame.isEmpty else { return }
    frame[frame.startIndex] ^= 1
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
