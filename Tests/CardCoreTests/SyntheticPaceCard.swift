// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoKit
import Foundation

/// A synthetic card that plays the card half of PACE with the same
/// mathematics, independently implemented, over any ``PaceCurve``.
///
/// This is what makes an offline PACE test meaningful. The card serves its
/// own EF.CardAccess, answers MSE:Set AT with the password state it was
/// given, picks its own nonce and its own two ephemeral scalars, derives
/// the mapped generator, the shared secret and the session keys by its own
/// code path, and computes the authentication tokens with its own key
/// derivation function written out here rather than taken from the module
/// under test. The nonce becomes a point by Horner's rule over points, one
/// octet at a time, with no reduction modulo the group order at all, so a
/// nonce wider than the order checks the terminal's reduction. If the
/// terminal and this card arrive at the same Kenc and Kmac, then every step
/// in between agreed as well. No hardware is involved.
internal final class SyntheticPaceCard<Curve: PaceCurve>: CardChannel {
  /// What the card is and how it answers.
  internal struct Configuration {
    /// The password the card expects, as its digits.
    internal var passwordDigits: String

    /// The MSE:Set AT password reference the card expects.
    internal var passwordReference: UInt8

    /// The domain parameter identifier the card expects.
    internal var domainParameter: UInt8

    /// The card's nonce, a whole number of AES blocks.
    internal var nonce: Data

    /// The card's ephemeral scalar for the generic mapping.
    internal var mappingScalar: U384

    /// The card's ephemeral scalar for the key agreement.
    internal var agreementScalar: U384

    /// The EF.CardAccess the card serves.
    internal var cardAccess: Data

    /// The status word MSE:Set AT answers, as hex.
    internal var authenticationTemplateStatusHex: String = SyntheticPaceCardValues.successHex

    /// The status word the last round answers when the terminal's token
    /// does not verify, as hex.
    internal var refusedTokenStatusHex: String = SyntheticPaceCardValues.authenticationFailedHex
  }

  /// Thrown when the terminal's command is not what the current round
  /// expects.
  internal struct Rejected: Error, Equatable {}

  private let configuration: Configuration

  /// The key that encrypts the nonce, derived from the password digits.
  private let passwordKey: Data

  /// The mapped generator, once the mapping round has run.
  private var mappedGenerator: CurvePoint<Curve>?

  /// The card's ephemeral public key on the mapped generator.
  private var cardPublicKey: CurvePoint<Curve>?

  /// The terminal's ephemeral public key on the mapped generator.
  private var terminalPublicKey: CurvePoint<Curve>?

  /// The card's own copy of Kmac.
  private var macKeyMaterial: Data?

  /// The session keys the card derived, available after the agreement.
  internal private(set) var sessionKeys: PaceSessionKeys?

  /// The instruction byte of every command received, in order.
  internal private(set) var instructions: [UInt8] = []

  /// How many GENERAL AUTHENTICATE commands arrived.
  internal var generalAuthenticateCount: Int {
    instructions.filter { $0 == SyntheticPaceCardValues.generalAuthenticate }.count
  }

  /// PACE runs before any secure messaging exists, so this card is a
  /// plain transport.
  internal var readChunkLength: ReadChunkLength {
    .plain
  }

  internal init(_ configuration: Configuration) {
    self.configuration = configuration
    self.passwordKey = Self.derivedKey(
      from: Data(configuration.passwordDigits.utf8),
      counter: SyntheticPaceCardValues.passwordCounter
    )
  }

  /// The ICAO Doc 9303 part 11 section 9.7.1.2 AES-256 key derivation,
  /// written out here so the test does not borrow the module's version.
  private static func derivedKey(from secret: Data, counter: UInt32) -> Data {
    var input = secret
    withUnsafeBytes(of: counter.bigEndian) { input.append(contentsOf: $0) }
    return Data(SHA256.hash(data: input))
  }

  /// One data object, refusing anything the encoder cannot represent.
  private static func object(tag: UInt8, value: Data) throws -> Data {
    guard let encoded = DerTlvRecord.encoded(tag: tag, value: value) else {
      throw Rejected()
    }
    return encoded
  }

  /// A `7C` template carrying one context data object, with the success
  /// status word appended.
  private static func response(contextTag: UInt8, value: Data) throws -> Data {
    let template = try Self.object(
      tag: SyntheticPaceCardValues.dynamicAuthenticationDataTag,
      value: try Self.object(tag: contextTag, value: value)
    )
    return template + WireHex.data(SyntheticPaceCardValues.successHex)
  }

  /// The SEC1 encoding of a point the protocol requires to be finite.
  private static func encodedPoint(_ point: CurvePoint<Curve>) throws -> Data {
    guard let encoded = point.encodeUncompressed() else { throw Rejected() }
    return encoded
  }

  /// The authentication token input `7F49 { 06 OID, 86 point }`.
  private static func tokenInput(for point: CurvePoint<Curve>) throws -> Data {
    let body =
      try Self.object(
        tag: SyntheticPaceCardValues.objectIdentifierTag,
        value: WireHex.data(SyntheticPaceCardValues.protocolOidHex)
      )
      + Self.object(
        tag: SyntheticPaceCardValues.publicKeyTemplatePointTag,
        value: try Self.encodedPoint(point)
      )
    let template = try Self.object(
      tag: SyntheticPaceCardValues.publicKeyTemplateSecondByte,
      value: body
    )
    return Data([SyntheticPaceCardValues.publicKeyTemplateFirstByte]) + template
  }

  /// `nonce * G` by Horner's rule over points, with no reduction.
  private static func nonceTimesGenerator(_ nonce: Data) -> CurvePoint<Curve> {
    var point = CurvePoint<Curve>.infinity
    for octet in nonce {
      for _ in 0..<SyntheticPaceCardValues.bitsPerOctet {
        point = point.doubled()
      }
      point = point.adding(Curve.multiplyGenerator(by: U384(UInt64(octet))))
    }
    return point
  }

  /// The data field of a short-form command.
  private static func body(of bytes: [UInt8]) throws -> Data {
    guard bytes.count > SyntheticPaceCardValues.lengthOffset else { throw Rejected() }
    let dataLength = Int(bytes[SyntheticPaceCardValues.lengthOffset])
    guard bytes.count >= SyntheticPaceCardValues.bodyOffset + dataLength else { throw Rejected() }
    return Data(
      bytes[SyntheticPaceCardValues.bodyOffset..<(SyntheticPaceCardValues.bodyOffset + dataLength)])
  }

  /// Answers one command APDU.
  internal func transmit(_ payload: Data) throws -> Data {
    let bytes = Array(payload)
    guard bytes.count >= SyntheticPaceCardValues.lengthOffset else { throw Rejected() }
    let instruction = bytes[SyntheticPaceCardValues.instructionOffset]
    instructions.append(instruction)
    switch instruction {
    case SyntheticPaceCardValues.select:
      return WireHex.data(SyntheticPaceCardValues.successHex)

    case SyntheticPaceCardValues.readBinary:
      return read(bytes)

    case SyntheticPaceCardValues.manageSecurityEnvironment:
      return try setAuthenticationTemplate(try Self.body(of: bytes))

    case SyntheticPaceCardValues.generalAuthenticate:
      return try round(try Self.body(of: bytes))

    default:
      throw Rejected()
    }
  }

  /// READ BINARY of EF.CardAccess at the offset P1-P2 names.
  private func read(_ bytes: [UInt8]) -> Data {
    let offset =
      Int(bytes[SyntheticPaceCardValues.parameterOneOffset]) << SyntheticPaceCardValues.bitsPerOctet
      | Int(bytes[SyntheticPaceCardValues.parameterTwoOffset])
    let asked =
      bytes.count > SyntheticPaceCardValues.lengthOffset
      ? Int(bytes[SyntheticPaceCardValues.lengthOffset]) : 0
    let length = asked == 0 ? SyntheticPaceCardValues.maximumShortLength : asked
    let file = configuration.cardAccess
    let start = min(offset, file.count)
    let end = min(start + length, file.count)
    return Data(file[start..<end]) + WireHex.data(SyntheticPaceCardValues.successHex)
  }

  /// MSE:Set AT: the suite, the password and the domain this card expects,
  /// answered with the configured password state.
  private func setAuthenticationTemplate(_ data: Data) throws -> Data {
    let objects = try DerTlvRecord.sequence(in: data)
    let mechanism = objects.first { $0.tag == SyntheticPaceCardValues.mechanismOrNonceTag }?.value
    let password = objects.first { $0.tag == SyntheticPaceCardValues.passwordOrTerminalKeyTag }?
      .value
    let domain = objects.first { $0.tag == SyntheticPaceCardValues.domainOrCardKeyTag }?.value
    guard
      mechanism == WireHex.data(SyntheticPaceCardValues.protocolOidHex),
      password == Data([configuration.passwordReference]),
      domain == Data([configuration.domainParameter])
    else {
      return WireHex.data(SyntheticPaceCardValues.incorrectDataHex)
    }
    return WireHex.data(configuration.authenticationTemplateStatusHex)
  }

  /// Dispatches one GENERAL AUTHENTICATE by the context tag it carries.
  private func round(_ data: Data) throws -> Data {
    let outer = try DerTlvRecord.sequence(in: data)
    guard
      let template = outer.first,
      template.tag == SyntheticPaceCardValues.dynamicAuthenticationDataTag
    else {
      throw Rejected()
    }
    let inner = try DerTlvRecord.sequence(in: template.value)
    guard let object = inner.first else { return try encryptedNonce() }
    switch object.tag {
    case SyntheticPaceCardValues.mappingDataTerminalTag:
      return try mapGenerator(terminalMappingData: object.value)

    case SyntheticPaceCardValues.passwordOrTerminalKeyTag:
      return try agree(terminalPublicKeyData: object.value)

    case SyntheticPaceCardValues.authenticationTokenTerminalTag:
      return try authenticate(terminalToken: object.value)

    default:
      throw Rejected()
    }
  }

  /// Round one: the nonce under the key the password derives.
  private func encryptedNonce() throws -> Data {
    let ciphertext = try AesCbc.encrypt(
      key: passwordKey,
      initializationVector: Data(repeating: 0, count: AesCbc.blockSize),
      plaintext: configuration.nonce
    )
    return try Self.response(
      contextTag: SyntheticPaceCardValues.mechanismOrNonceTag, value: ciphertext)
  }

  /// Round two: the generic mapping, `G' = s*G + H`.
  private func mapGenerator(terminalMappingData: Data) throws -> Data {
    guard let terminalPoint = CurvePoint<Curve>.decodeUncompressed(terminalMappingData) else {
      throw Rejected()
    }
    let shared = Curve.multiply(terminalPoint, by: configuration.mappingScalar)
    mappedGenerator = Self.nonceTimesGenerator(configuration.nonce).adding(shared)
    return try Self.response(
      contextTag: SyntheticPaceCardValues.mappingDataCardTag,
      value: try Self.encodedPoint(Curve.multiplyGenerator(by: configuration.mappingScalar))
    )
  }

  /// Round three: the key agreement on the mapped generator, and the key
  /// derivation from the agreed point's x-coordinate in the field width.
  private func agree(terminalPublicKeyData: Data) throws -> Data {
    guard
      let mappedGenerator,
      let terminalPoint = CurvePoint<Curve>.decodeUncompressed(terminalPublicKeyData)
    else {
      throw Rejected()
    }
    terminalPublicKey = terminalPoint
    let publicKey = Curve.multiply(mappedGenerator, by: configuration.agreementScalar)
    cardPublicKey = publicKey
    let shared = Curve.multiply(terminalPoint, by: configuration.agreementScalar)
    guard let horizontal = shared.affineX else { throw Rejected() }
    let secret = Data(horizontal.bigEndianBytes().suffix(Curve.coordinateByteCount))
    let derivedMacKey = Self.derivedKey(from: secret, counter: SyntheticPaceCardValues.macCounter)
    macKeyMaterial = derivedMacKey
    sessionKeys = PaceSessionKeys(
      encryptionKey: Self.derivedKey(
        from: secret, counter: SyntheticPaceCardValues.encryptionCounter),
      macKey: derivedMacKey
    )
    return try Self.response(
      contextTag: SyntheticPaceCardValues.domainOrCardKeyTag,
      value: try Self.encodedPoint(publicKey)
    )
  }

  /// Round four: check the terminal's token and answer with the card's,
  /// or with the configured refusal.
  private func authenticate(terminalToken: Data) throws -> Data {
    guard
      let cardPublicKey,
      let terminalPublicKey,
      let macKey = macKeyMaterial
    else {
      throw Rejected()
    }
    let expected = try AesCmac.secureMessagingTag(
      key: macKey,
      message: try Self.tokenInput(for: cardPublicKey)
    )
    guard expected == terminalToken else {
      return WireHex.data(configuration.refusedTokenStatusHex)
    }
    let cardToken = try AesCmac.secureMessagingTag(
      key: macKey,
      message: try Self.tokenInput(for: terminalPublicKey)
    )
    return try Self.response(
      contextTag: SyntheticPaceCardValues.authenticationTokenCardTag,
      value: cardToken
    )
  }
}
