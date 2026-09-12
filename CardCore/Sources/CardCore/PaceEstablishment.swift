// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// PACE-ECDH-GM-AES-CBC-CMAC-256 over brainpoolP384r1 with the CAN: the
/// FINEID card's contactless door.
///
/// MSE:Set AT names the suite, the password (the CAN) and the curve; four
/// GENERAL AUTHENTICATE rounds then run the protocol. Round one returns a
/// nonce encrypted under a key derived from the CAN, so only a terminal that
/// knows the CAN learns `s`. Round two exchanges ephemeral public points and
/// the generic mapping turns them into a fresh generator `G' = s*G + H`,
/// where `H` is the ordinary ECDH point of that exchange. Round three is a
/// second ephemeral exchange, this time on `G'`, whose shared point's
/// x-coordinate is the PACE shared secret. Round four exchanges
/// authentication tokens: each side MACs the point the other sent, so
/// neither uses the session until it has evidence the other derived the same
/// keys. Only the last round clears the command-chaining bit.
///
/// What comes out is `PaceSessionKeys`. Turning that into a channel is
/// `SecureMessagingChannel`'s job, and it is the only thing the keys are
/// good for.
///
/// Failing PACE consumes no retry counter -- the CAN has none -- so a wrong
/// CAN is a recoverable user error, unlike a wrong PIN.
///
/// Provenance: lifted from the RefineID iOS browser donor
/// `Sources/RefineIDBrowserKit/Card/Pace.swift`, which was in turn ported
/// byte-exact from the Rust reference implementation and proven against a
/// live card.
public struct PaceEstablishment {
  /// Why a PACE run was abandoned.
  ///
  /// Every case is terminal for the attempt: no round can be retried on the
  /// same session, because each one consumes the card's protocol state.
  public enum Failure: Error, Equatable {
    /// The card's authentication token did not match the one derived from
    /// this side's keys. The two sides hold different keys; the session is
    /// abandoned, never retried on these keys.
    case authenticationTokenMismatch

    /// The card answered a PACE command with something other than success.
    case cardRejected(StatusWord)

    /// A response was not the dynamic authentication data the round
    /// expects, or a command could not be encoded within the short form.
    case malformedResponse

    /// A point the protocol requires to be finite was the point at
    /// infinity, so it has neither an encoding nor an x-coordinate.
    case unusablePoint
  }

  /// The PACE nonce length: one AES block (ICAO 9303-11 section 9.7.3).
  private static let nonceLength: Int = AesCbc.blockSize

  /// The transport this run drives.
  private let channel: any CardChannel

  /// Where the two ephemeral private scalars come from.
  private let scalarSource: PaceEphemeralScalarSource

  /// A run over `channel` using the platform CSPRNG for its scalars.
  public init(channel: any CardChannel) {
    self.channel = channel
    self.scalarSource = .secureRandom
  }

  /// A run over `channel` drawing its scalars from `scalarSource`.
  ///
  /// Only tests pass anything but `.secureRandom`.
  public init(channel: any CardChannel, scalarSource: PaceEphemeralScalarSource) {
    self.channel = channel
    self.scalarSource = scalarSource
  }

  /// The mapped generator `G' = s*G + H` of the generic mapping.
  ///
  /// The nonce becomes a scalar by zero-extending its 16 big-endian bytes
  /// to the 384-bit width, with no reduction modulo the group order: that
  /// is what ICAO 9303-11 section 9.7.3 prescribes and what the card does.
  private static func mappedGenerator(
    nonce: Data,
    cardMappingPoint: BrainpoolPoint,
    mappingScalar: U384
  ) throws -> BrainpoolPoint {
    guard let nonceScalar = U384(bigEndianBytes: nonce) else {
      throw Failure.malformedResponse
    }
    let shared = BrainpoolP384r1.multiply(cardMappingPoint, by: mappingScalar)
    return BrainpoolP384r1.multiplyGenerator(by: nonceScalar).adding(shared)
  }

  /// The session keys derived from the agreed point.
  ///
  /// Only the x-coordinate enters the derivation, per ICAO 9303-11
  /// section 9.7.4; the point at infinity has none, which is a protocol
  /// failure rather than a zero secret.
  private static func sessionKeys(sharedSecret: BrainpoolPoint) throws -> PaceSessionKeys {
    guard let horizontal = sharedSecret.affineX else {
      throw Failure.unusablePoint
    }
    let secret = horizontal.bigEndianBytes()
    guard
      let keys = PaceSessionKeys(
        encryptionKey: PaceKeyDerivation.derivedKey(from: secret, for: .encryption),
        macKey: PaceKeyDerivation.derivedKey(from: secret, for: .mac)
      )
    else {
      throw Failure.malformedResponse
    }
    return keys
  }

  /// Runs PACE with `accessNumber` and returns the session keys.
  ///
  /// The CAN is used for exactly one thing, in one place: deriving the key
  /// that deciphers the nonce. It is not retained past that point.
  public func establish(with accessNumber: CardAccessNumber) throws -> PaceSessionKeys {
    guard let environment = PaceCommand.securityEnvironment() else {
      throw Failure.malformedResponse
    }
    _ = try transmit(environment)

    let nonce = try recoverNonce(with: accessNumber)

    let mappingScalar = scalarSource.nextScalar()
    let cardMappingPoint = try exchangeMappingData(mappingScalar: mappingScalar)
    let mappedGenerator = try Self.mappedGenerator(
      nonce: nonce,
      cardMappingPoint: cardMappingPoint,
      mappingScalar: mappingScalar
    )

    let agreementScalar = scalarSource.nextScalar()
    let terminalPublicKey = BrainpoolP384r1.multiply(mappedGenerator, by: agreementScalar)
    let cardPublicKey = try exchangeEphemeralKeys(terminalPublicKey: terminalPublicKey)
    let keys = try Self.sessionKeys(
      sharedSecret: BrainpoolP384r1.multiply(cardPublicKey, by: agreementScalar)
    )

    try confirm(
      keys: keys,
      terminalPublicKey: terminalPublicKey,
      cardPublicKey: cardPublicKey
    )
    return keys
  }

  /// Round one: fetch the encrypted nonce and decipher it with the key the
  /// CAN derives.
  ///
  /// The nonce is exactly one block and travels unpadded, so the recovered
  /// buffer is used whole. A wrong CAN yields a wrong nonce here and
  /// surfaces three rounds later as a token mismatch, which is by design:
  /// the card must not learn early that the guess was wrong.
  private func recoverNonce(with accessNumber: CardAccessNumber) throws -> Data {
    guard let template = PaceDataObject.emptyDynamicAuthenticationData() else {
      throw Failure.malformedResponse
    }
    let response = try generalAuthenticate(
      template: template,
      classByte: Iso7816Values.classCommandChaining
    )
    let encryptedNonce = try PaceDataObject.value(
      in: response,
      contextTag: PaceValues.encryptedNonceTag
    )
    guard encryptedNonce.count == Self.nonceLength else {
      throw Failure.malformedResponse
    }
    return try AesCbc.decrypt(
      key: accessNumber.derivedPasswordKey(),
      initializationVector: Data(repeating: 0, count: AesCbc.blockSize),
      ciphertext: encryptedNonce
    )
  }

  /// Round two: send the terminal's mapping point, receive the card's.
  private func exchangeMappingData(mappingScalar: U384) throws -> BrainpoolPoint {
    let terminalPoint = BrainpoolP384r1.multiplyGenerator(by: mappingScalar)
    let response = try roundTrip(
      contextTag: PaceValues.mappingDataTerminalTag,
      value: try PaceDataObject.encodedPoint(terminalPoint),
      classByte: Iso7816Values.classCommandChaining
    )
    return try PaceDataObject.point(
      in: response,
      contextTag: PaceValues.mappingDataCardTag
    )
  }

  /// Round three: send the terminal's ephemeral public key on the mapped
  /// generator, receive the card's.
  private func exchangeEphemeralKeys(
    terminalPublicKey: BrainpoolPoint
  ) throws -> BrainpoolPoint {
    let response = try roundTrip(
      contextTag: PaceValues.ephemeralPublicKeyTerminalTag,
      value: try PaceDataObject.encodedPoint(terminalPublicKey),
      classByte: Iso7816Values.classCommandChaining
    )
    return try PaceDataObject.point(
      in: response,
      contextTag: PaceValues.ephemeralPublicKeyCardTag
    )
  }

  /// Round four: exchange authentication tokens and check the card's.
  ///
  /// Each side MACs the point the OTHER sent, so a matching token is
  /// evidence that the card derived the same Kmac -- and therefore the same
  /// Kenc -- from the same shared secret. This is the round that clears the
  /// chaining bit, which is how the card knows PACE is complete.
  private func confirm(
    keys: PaceSessionKeys,
    terminalPublicKey: BrainpoolPoint,
    cardPublicKey: BrainpoolPoint
  ) throws {
    let terminalToken = try AesCmac.secureMessagingTag(
      key: keys.macKey,
      message: try PaceDataObject.authenticationTokenInput(for: cardPublicKey)
    )
    let response = try roundTrip(
      contextTag: PaceValues.authenticationTokenTerminalTag,
      value: terminalToken,
      classByte: Iso7816Values.classInterindustry
    )
    let cardToken = try PaceDataObject.value(
      in: response,
      contextTag: PaceValues.authenticationTokenCardTag
    )
    let expected = try AesCmac.secureMessagingTag(
      key: keys.macKey,
      message: try PaceDataObject.authenticationTokenInput(for: terminalPublicKey)
    )
    guard ConstantTimeComparison.equal(expected, cardToken) else {
      throw Failure.authenticationTokenMismatch
    }
  }

  /// One GENERAL AUTHENTICATE carrying a single context data object.
  private func roundTrip(contextTag: UInt8, value: Data, classByte: UInt8) throws -> Data {
    guard
      let template = PaceDataObject.dynamicAuthenticationData(
        contextTag: contextTag,
        value: value
      )
    else {
      throw Failure.malformedResponse
    }
    return try generalAuthenticate(template: template, classByte: classByte)
  }

  /// Sends one GENERAL AUTHENTICATE and returns its payload.
  private func generalAuthenticate(template: Data, classByte: UInt8) throws -> Data {
    guard
      let command = PaceCommand.generalAuthenticate(
        template: template,
        classByte: classByte
      )
    else {
      throw Failure.malformedResponse
    }
    return try transmit(command)
  }

  /// Transmits one command, follows any `61xx`, and insists on success.
  private func transmit(_ command: Data) throws -> Data {
    let response = try ContinuedResponse.transmitting(command, over: channel)
    guard response.statusWord == .success else {
      throw Failure.cardRejected(response.statusWord)
    }
    return response.payload
  }
}
