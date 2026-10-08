// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// An in-progress session handshake over a stored pairing.
internal struct SessionHandshake {
  private let role: EndpointRole

  private let pairIdentifier: Data

  private let expectedParameters: SessionParameters

  private var noise: NoiseHandshakeState

  internal var isComplete: Bool { noise.isComplete }

  /// Start a session the local user asked for.
  ///
  /// Requester side only.
  internal static func beginRequester(
    pair: PairRecord, intent: ExplicitUserIntent
  ) throws -> Self {
    _ = intent
    guard pair.role == .requester else { throw SessionError.roleViolation }
    return try begin(pair: pair)
  }

  /// Answer one incoming connection.
  ///
  /// Proxy side only; never initiates.
  internal static func beginProxy(pair: PairRecord) throws -> Self {
    guard pair.role == .proxy else { throw SessionError.roleViolation }
    return try begin(pair: pair)
  }

  private static func begin(pair: PairRecord) throws -> Self {
    do {
      let decodedNoise = try NoiseHandshakeState(
        pattern: .knownKnown,
        suiteName: RappNoise.sessionSuite,
        prologue: try RappNoise.sessionPrologue(
          pairIdentifier: pair.pairIdentifier,
          grantsHash: pair.grantsHash,
          transportProfile: pair.transport.profile),
        isInitiator: pair.role == .requester,
        localStaticPrivate: pair.localStaticPrivate,
        remoteStaticPublic: pair.remoteStaticPublic,
        presharedKey: nil,
        fixedEphemeralPrivate: Curve25519.KeyAgreement.PrivateKey().rawRepresentation)
      return Self(
        role: pair.role,
        pairIdentifier: pair.pairIdentifier,
        expectedParameters: SessionParameters(
          transportProfile: pair.transport.profile,
          candidateIdentifier: pair.transport.candidateIdentifier,
          grantsHash: pair.grantsHash),
        noise: decodedNoise)
    } catch {
      throw SessionError.noise
    }
  }

  internal mutating func writeMessage() throws -> Data {
    do {
      return try noise.writeMessage()
    } catch {
      throw SessionError.noise
    }
  }

  internal mutating func readMessage(_ frame: Data) throws {
    let payload: Data
    do {
      payload = try noise.readMessage(frame)
    } catch {
      throw SessionError.noise
    }
    guard payload.isEmpty else { throw SessionError.noise }
  }

  /// Complete the handshake and enter mutual parameter verification.
  internal consuming func intoAuthentication() throws -> SessionAuthentication {
    guard noise.isComplete else { throw SessionError.noise }
    let split: (send: NoiseCipherState, receive: NoiseCipherState)
    do {
      split = try noise.split()
    } catch {
      throw SessionError.noise
    }
    let sessionIdentifier = RappNoise.sessionIdentifier(handshakeHash: noise.handshakeHash)
    return SessionAuthentication(
      role: role,
      pairIdentifier: pairIdentifier,
      sessionIdentifier: sessionIdentifier,
      expectedParameters: expectedParameters,
      channel: RappMessageChannel(
        channel: RappSecureChannel(send: split.send, receive: split.receive),
        sessionIdentifier: sessionIdentifier))
  }
}
