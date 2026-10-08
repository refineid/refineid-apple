// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// One party's view of a Noise handshake.
///
/// The state advances one message at a time and refuses to write out of turn,
/// so a caller cannot skip a token sequence the pattern requires.
internal struct NoiseHandshakeState {
  /// The initiator writes the even-numbered messages.
  private static let messagesPerRound = 2

  private var symmetric: NoiseSymmetricState
  private let pattern: NoisePattern
  private let isInitiator: Bool
  private let presharedKey: Data?

  private let localStaticPrivate: Data
  private let localStaticPublic: Data
  private var localEphemeralPrivate: Data?
  private var localEphemeralPublic: Data?
  private var remoteStatic: Data?
  private var remoteEphemeral: Data?

  private var messageIndex = 0

  internal var authenticatedRemoteStatic: Data? { remoteStatic }
  internal var isComplete: Bool { messageIndex >= pattern.messages.count }
  internal var handshakeHash: Data { symmetric.handshakeHash }

  private var localWritesNext: Bool {
    messageIndex.isMultiple(of: Self.messagesPerRound) == isInitiator
  }

  internal init(
    pattern: NoisePattern,
    suiteName: String,
    prologue: Data,
    isInitiator: Bool,
    localStaticPrivate: Data,
    remoteStaticPublic: Data?,
    presharedKey: Data?,
    fixedEphemeralPrivate: Data?
  ) throws {
    self.pattern = pattern
    self.isInitiator = isInitiator
    self.presharedKey = presharedKey
    self.localStaticPrivate = localStaticPrivate
    self.localStaticPublic = try Self.publicKey(from: localStaticPrivate)
    self.remoteStatic = remoteStaticPublic
    if let fixedEphemeralPrivate {
      self.localEphemeralPrivate = fixedEphemeralPrivate
      self.localEphemeralPublic = try Self.publicKey(from: fixedEphemeralPrivate)
    }

    symmetric = NoiseSymmetricState(protocolName: suiteName)
    symmetric.mixHash(prologue)

    for token in pattern.initiatorPreMessage where token == .staticKey {
      symmetric.mixHash(isInitiator ? localStaticPublic : (remoteStatic ?? Data()))
    }
    for token in pattern.responderPreMessage where token == .staticKey {
      symmetric.mixHash(isInitiator ? (remoteStatic ?? Data()) : localStaticPublic)
    }
  }

  private static func publicKey(from privateKey: Data) throws -> Data {
    try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
      .publicKey.rawRepresentation
  }

  private static func agree(privateKey: Data, publicKey: Data) throws -> Data {
    let local = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
    let remote = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey)
    return try local.sharedSecretFromKeyAgreement(with: remote).withUnsafeBytes { Data($0) }
  }

  private mutating func mixDiffieHellman(_ token: NoiseToken) throws {
    let material: Data
    switch token {
    case .ephemeralEphemeral:
      guard let localEphemeralPrivate, let remoteEphemeral else {
        throw NoiseError.missingKeyMaterial
      }
      material = try Self.agree(privateKey: localEphemeralPrivate, publicKey: remoteEphemeral)

    case .ephemeralStatic:
      material = try mixedEphemeralStatic()

    case .staticEphemeral:
      material = try mixedStaticEphemeral()

    case .staticStatic:
      guard let remoteStatic else { throw NoiseError.missingKeyMaterial }
      material = try Self.agree(privateKey: localStaticPrivate, publicKey: remoteStatic)

    default:
      throw NoiseError.missingKeyMaterial
    }
    symmetric.mixKey(material)
  }

  /// The initiator's ephemeral meets the responder's static.
  private func mixedEphemeralStatic() throws -> Data {
    if isInitiator {
      guard let localEphemeralPrivate, let remoteStatic else {
        throw NoiseError.missingKeyMaterial
      }
      return try Self.agree(privateKey: localEphemeralPrivate, publicKey: remoteStatic)
    }
    guard let remoteEphemeral else { throw NoiseError.missingKeyMaterial }
    return try Self.agree(privateKey: localStaticPrivate, publicKey: remoteEphemeral)
  }

  /// The initiator's static meets the responder's ephemeral.
  private func mixedStaticEphemeral() throws -> Data {
    if isInitiator {
      guard let remoteEphemeral else { throw NoiseError.missingKeyMaterial }
      return try Self.agree(privateKey: localStaticPrivate, publicKey: remoteEphemeral)
    }
    guard let localEphemeralPrivate, let remoteStatic else {
      throw NoiseError.missingKeyMaterial
    }
    return try Self.agree(privateKey: localEphemeralPrivate, publicKey: remoteStatic)
  }

  private mutating func writeEphemeralToken(into buffer: inout Data) throws {
    guard let localEphemeralPublic else { throw NoiseError.missingKeyMaterial }
    buffer += localEphemeralPublic
    symmetric.mixHash(localEphemeralPublic)
    if pattern.usesPresharedKey { symmetric.mixKey(localEphemeralPublic) }
  }

  private mutating func writeToken(_ token: NoiseToken, into buffer: inout Data) throws {
    switch token {
    case .ephemeral:
      try writeEphemeralToken(into: &buffer)
    case .staticKey:
      buffer += try symmetric.encryptAndHash(localStaticPublic)
    case .presharedKey:
      guard let presharedKey else { throw NoiseError.missingKeyMaterial }
      symmetric.mixKeyAndHash(presharedKey)
    default:
      try mixDiffieHellman(token)
    }
  }

  internal mutating func writeMessage() throws -> Data {
    try writeMessage(payload: Data())
  }

  internal mutating func writeMessage(payload: Data) throws -> Data {
    guard !isComplete, localWritesNext else { throw NoiseError.wrongTurn }
    var buffer = Data()
    for token in pattern.messages[messageIndex] {
      try writeToken(token, into: &buffer)
    }
    buffer += try symmetric.encryptAndHash(payload)
    messageIndex += 1
    return buffer
  }

  private func takeBytes(_ count: Int, from rest: inout Data) throws -> Data {
    guard rest.count >= count else { throw NoiseError.malformedMessage }
    let head = Data(rest.prefix(count))
    rest = Data(rest.dropFirst(count))
    return head
  }

  private mutating func readEphemeralToken(from rest: inout Data) throws {
    let key = try takeBytes(NoiseSizes.publicKeyLength, from: &rest)
    remoteEphemeral = key
    symmetric.mixHash(key)
    if pattern.usesPresharedKey { symmetric.mixKey(key) }
  }

  private mutating func readStaticKeyToken(from rest: inout Data) throws {
    let length =
      symmetric.cipher.hasKey
      ? NoiseSizes.publicKeyLength + NoiseSizes.tagLength : NoiseSizes.publicKeyLength
    remoteStatic = try symmetric.decryptAndHash(try takeBytes(length, from: &rest))
  }

  private mutating func readToken(_ token: NoiseToken, from rest: inout Data) throws {
    switch token {
    case .ephemeral:
      try readEphemeralToken(from: &rest)
    case .staticKey:
      try readStaticKeyToken(from: &rest)
    case .presharedKey:
      guard let presharedKey else { throw NoiseError.missingKeyMaterial }
      symmetric.mixKeyAndHash(presharedKey)
    default:
      try mixDiffieHellman(token)
    }
  }

  internal mutating func readMessage(_ message: Data) throws -> Data {
    guard !isComplete, !localWritesNext else { throw NoiseError.wrongTurn }
    var rest = message
    for token in pattern.messages[messageIndex] {
      try readToken(token, from: &rest)
    }
    let payload = try symmetric.decryptAndHash(rest)
    messageIndex += 1
    return payload
  }

  /// The two transport directions, once the pattern has completed.
  internal func split() throws -> (send: NoiseCipherState, receive: NoiseCipherState) {
    guard isComplete else { throw NoiseError.handshakeIncomplete }
    let (first, second) = symmetric.split()
    var send = NoiseCipherState()
    var receive = NoiseCipherState()
    send.initializeKey(isInitiator ? first : second)
    receive.initializeKey(isInitiator ? second : first)
    return (send, receive)
  }
}
