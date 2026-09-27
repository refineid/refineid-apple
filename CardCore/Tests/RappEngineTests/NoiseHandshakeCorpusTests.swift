// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
//
// Replays the fixed handshake transcripts. The keys are corpus test vectors.

import CryptoKit
import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP Noise handshakes against the vendored corpus")
internal struct NoiseHandshakeCorpusTests {
  private struct Parties {
    let initiator: NoiseHandshakeState
    let responder: NoiseHandshakeState
    let prologue: Data
    let initiatorStaticPublic: Data
    let responderStaticPublic: Data
  }

  /// Counters only advance past one after several exchanges, so the round
  /// trip is repeated rather than run once.
  private static let roundTripCount = 3

  private static func publicKey(from privateKey: Data) throws -> Data {
    try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
      .publicKey.rawRepresentation
  }

  private static func parties(for vector: NoiseVector) throws -> Parties {
    let initiatorStatic = try Data(hex: vector.testOnlyInitiatorStaticPrivateHex)
    let responderStatic = try Data(hex: vector.testOnlyResponderStaticPrivateHex)
    let initiatorEphemeral = try Data(hex: vector.testOnlyInitiatorEphemeralPrivateHex)
    let responderEphemeral = try Data(hex: vector.testOnlyResponderEphemeralPrivateHex)
    let initiatorPublic = try publicKey(from: initiatorStatic)
    let responderPublic = try publicKey(from: responderStatic)

    let isPairing = vector.name.contains("pairing") || vector.suite.contains("XXpsk3")
    let prologue =
      isPairing
      ? try RappNoise.pairingPrologue(
        offerHash: try Data(hex: vector.offerHashHex ?? ""),
        transportProfile: vector.transportProfile,
        suite: vector.suite)
      : try RappNoise.sessionPrologue(
        pairIdentifier: try Data(hex: vector.pairIDHex),
        grantsHash: try Data(hex: vector.grantsHashHex ?? ""),
        transportProfile: vector.transportProfile,
        suite: vector.suite)

    let pattern = isPairing ? NoisePattern.xxPsk3 : NoisePattern.knownKnown
    let secret = isPairing ? try Data(hex: vector.testOnlyPairingSecretHex ?? "") : nil

    return Parties(
      initiator: try NoiseHandshakeState(
        pattern: pattern, suiteName: vector.suite, prologue: prologue, isInitiator: true,
        localStaticPrivate: initiatorStatic,
        remoteStaticPublic: isPairing ? nil : responderPublic,
        presharedKey: secret, fixedEphemeralPrivate: initiatorEphemeral),
      responder: try NoiseHandshakeState(
        pattern: pattern, suiteName: vector.suite, prologue: prologue, isInitiator: false,
        localStaticPrivate: responderStatic,
        remoteStaticPublic: isPairing ? nil : initiatorPublic,
        presharedKey: secret, fixedEphemeralPrivate: responderEphemeral),
      prologue: prologue,
      initiatorStaticPublic: initiatorPublic,
      responderStaticPublic: responderPublic)
  }
  @Test("Each fixed transcript is reproduced byte for byte")
  internal func fixedTranscripts() throws {
    for vector in try CorpusFile.conformance(filePath: #filePath).noiseHandshake {
      let parties = try Self.parties(for: vector)
      var initiator = parties.initiator
      var responder = parties.responder

      #expect(parties.prologue.hex == vector.prologueHex, "\(vector.name)")
      #expect(parties.initiatorStaticPublic.hex == vector.initiatorStaticPublicHex)
      #expect(parties.responderStaticPublic.hex == vector.responderStaticPublicHex)

      for (index, expected) in vector.messagesHex.enumerated() {
        let initiatorWrites = index.isMultiple(of: 2)
        let message =
          initiatorWrites ? try initiator.writeMessage() : try responder.writeMessage()
        let payload =
          initiatorWrites ? try responder.readMessage(message) : try initiator.readMessage(message)
        #expect(payload.isEmpty, "\(vector.name) message \(index + 1) carried a payload")
        #expect(message.hex == expected, "\(vector.name) message \(index + 1)")
      }

      #expect(initiator.isComplete, "\(vector.name)")
      #expect(responder.isComplete, "\(vector.name)")
      #expect(initiator.handshakeHash.hex == vector.handshakeHashHex, "\(vector.name)")
      #expect(responder.handshakeHash.hex == vector.handshakeHashHex, "\(vector.name)")

      let hash = initiator.handshakeHash
      #expect(RappNoise.sessionIdentifier(handshakeHash: hash).hex == vector.sessionIDHex)
      let isPairing = vector.name.contains("pairing") || vector.suite.contains("XXpsk3")
      if isPairing {
        #expect(RappNoise.pairIdentifier(handshakeHash: hash).hex == vector.pairIDHex)
        #expect(
          RappNoise.rendezvousToken(handshakeHash: hash).hex == vector.rendezvousTokenHex)
      }

      #expect(initiator.authenticatedRemoteStatic == parties.responderStaticPublic)
      #expect(responder.authenticatedRemoteStatic == parties.initiatorStaticPublic)
    }
  }

  @Test("The established channel carries traffic in both directions")
  internal func transportRoundTrip() throws {
    for vector in try CorpusFile.conformance(filePath: #filePath).noiseHandshake {
      let parties = try Self.parties(for: vector)
      var initiator = parties.initiator
      var responder = parties.responder
      for index in vector.messagesHex.indices {
        if index.isMultiple(of: 2) {
          _ = try responder.readMessage(try initiator.writeMessage())
        } else {
          _ = try initiator.readMessage(try responder.writeMessage())
        }
      }

      let initiatorSplit = try initiator.split()
      let responderSplit = try responder.split()
      var toProxy = RappSecureChannel(
        send: initiatorSplit.send, receive: initiatorSplit.receive)
      var toRequester = RappSecureChannel(
        send: responderSplit.send, receive: responderSplit.receive)

      let outbound = Data("requester to proxy".utf8)
      let inbound = Data("proxy to requester".utf8)
      for _ in 0..<Self.roundTripCount {
        #expect(try toRequester.open(try toProxy.seal(outbound)) == outbound, "\(vector.name)")
        #expect(try toProxy.open(try toRequester.seal(inbound)) == inbound, "\(vector.name)")
      }
    }
  }
}
