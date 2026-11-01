// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The MSE:Set AT and GENERAL AUTHENTICATE rounds of one PACE run.
extension PaceEstablishment {
  /// The session keys derived from the agreed point.
  ///
  /// Only the x-coordinate enters the derivation, in the curve's field
  /// width (ICAO Doc 9303 Part 11 section 4.4.3.4; SEC 1 v2 section
  /// 2.3.5); the point at infinity has none, which is a protocol failure
  /// rather than a zero secret.
  internal static func sessionKeys<Curve: PaceCurve>(
    sharedSecret: CurvePoint<Curve>
  ) throws -> PaceSessionKeys {
    guard let horizontal = sharedSecret.affineX else {
      throw Failure.unusablePoint
    }
    let secret = CurvePoint<Curve>.fieldBytes(horizontal)
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

  internal func nextScalar<Curve: PaceCurve>(_: Curve.Type) -> U384 {
    scalarSource.nextScalar(below: Curve.order, byteCount: Curve.coordinateByteCount)
  }

  internal func reportPhase(_ phase: String, since started: ContinuousClock.Instant) {
    let elapsed = TraceTiming.milliseconds(started.duration(to: ContinuousClock.now))
    diagnostic?("PACE phase=\(phase) elapsedMs=\(elapsed)")
  }

  /// MSE:Set AT, and for a PIN the retry floor on its answer.
  ///
  /// The answer to a PIN password is the PIN's state (BSI TR-03110-3
  /// section B.14.1): `9000` while the PIN has its initial tries, five on
  /// the organization card (FINEID S4-2 v4.0 section 4.3), `63CX` for X
  /// tries left, `6283` for a deactivated PIN. Below the floor nothing
  /// further is sent.
  internal func setAuthenticationTemplate(
    suite: PaceInfo,
    password: borrowing PacePassword
  ) throws -> RetryProbeOutcome? {
    guard
      let command = PaceCommand.securityEnvironment(
        suite: suite,
        passwordReference: password.reference
      )
    else {
      throw Failure.malformedResponse
    }
    let response = try ContinuedResponse.transmitting(command, over: channel)
    guard password.credential != nil else {
      guard response.statusWord == .success else {
        throw Failure.cardRejected(response.statusWord)
      }
      return nil
    }
    let state: RetryProbeOutcome
    switch response.statusWord {
    case .success:
      guard let initial = RetryCount(attemptsRemaining: RetryCount.pristineAllowance) else {
        throw Failure.malformedResponse
      }
      state = .remaining(initial)

    case .pinIncorrect(let remaining):
      state = remaining.isBlocked ? .locked : .remaining(remaining)

    case .authenticationBlocked:
      state = .locked

    case .other(PaceValues.swPasswordDeactivated):
      throw Failure.passwordDeactivated

    default:
      throw Failure.cardRejected(response.statusWord)
    }
    let verdict = RetryFloor.evaluate(probeOutcome: state)
    guard verdict == .proceed else {
      throw Failure.retryFloorRefused(verdict, state)
    }
    return state
  }

  /// Round one: fetch the encrypted nonce and decipher it with the key the
  /// password derives.
  ///
  /// The card chooses the nonce length, a whole number of AES blocks (ICAO
  /// Doc 9303 Part 11 section 4.4.3.3): one on the citizen cards, two on
  /// the organization card. One to four blocks are accepted and every
  /// block is deciphered in CBC mode under the all-zero IV; any other
  /// length is refused before the next command. A wrong password yields a
  /// wrong nonce here and surfaces three rounds later, which is by design:
  /// the card must not learn early that the guess was wrong.
  internal func recoverNonce(with password: borrowing PacePassword) throws -> Data {
    guard let template = PaceDataObject.emptyDynamicAuthenticationData() else {
      throw Failure.malformedResponse
    }
    let response = try generalAuthenticate(
      template: template,
      classByte: Iso7816Values.classCommandChaining,
      password: password
    )
    let encryptedNonce = try PaceDataObject.value(
      in: response,
      contextTag: PaceValues.encryptedNonceTag
    )
    let blocks = encryptedNonce.count / AesCbc.blockSize
    guard
      encryptedNonce.count.isMultiple(of: AesCbc.blockSize),
      (1...PaceValues.nonceMaximumBlockCount).contains(blocks)
    else {
      throw Failure.malformedResponse
    }
    return try AesCbc.decrypt(
      key: password.key,
      initializationVector: Data(repeating: 0, count: AesCbc.blockSize),
      ciphertext: encryptedNonce
    )
  }

  /// Rounds two and three: send the terminal's point, receive the card's,
  /// and refuse the card's when it reflects the terminal's own (ICAO Doc
  /// 9303 Part 11 section 4.4.1, step 4 d; the mapping exchange gets the
  /// same check), before anything derived from it is computed or sent.
  internal func exchange<Curve: PaceCurve>(
    _ terminalPoint: CurvePoint<Curve>,
    terminalTag: UInt8,
    cardTag: UInt8,
    password: borrowing PacePassword
  ) throws -> CurvePoint<Curve> {
    let response = try roundTrip(
      contextTag: terminalTag,
      value: try PaceDataObject.encodedPoint(terminalPoint),
      classByte: Iso7816Values.classCommandChaining,
      password: password
    )
    let cardPoint: CurvePoint<Curve> = try PaceDataObject.point(in: response, contextTag: cardTag)
    guard cardPoint != terminalPoint else {
      throw Failure.reflectedPoint
    }
    return cardPoint
  }

  /// Round four: exchange authentication tokens and check the card's.
  ///
  /// Each side MACs the point the OTHER sent, so a matching token is
  /// evidence that the card derived the same Kmac -- and therefore the same
  /// Kenc -- from the same shared secret. This is the round that clears the
  /// chaining bit, which is how the card knows PACE is complete.
  internal func confirm<Curve: PaceCurve>(
    keys: PaceSessionKeys,
    suite: PaceInfo,
    terminalPublicKey: CurvePoint<Curve>,
    cardPublicKey: CurvePoint<Curve>,
    password: borrowing PacePassword
  ) throws {
    let terminalToken = try AesCmac.secureMessagingTag(
      key: keys.macKey,
      message: try PaceDataObject.authenticationTokenInput(for: cardPublicKey, suite: suite)
    )
    let response = try roundTrip(
      contextTag: PaceValues.authenticationTokenTerminalTag,
      value: terminalToken,
      classByte: Iso7816Values.classInterindustry,
      password: password
    )
    let cardToken = try PaceDataObject.value(
      in: response,
      contextTag: PaceValues.authenticationTokenCardTag
    )
    let expected = try AesCmac.secureMessagingTag(
      key: keys.macKey,
      message: try PaceDataObject.authenticationTokenInput(for: terminalPublicKey, suite: suite)
    )
    guard ConstantTimeComparison.equal(expected, cardToken) else {
      throw Failure.authenticationTokenMismatch
    }
  }

  /// One GENERAL AUTHENTICATE carrying a single context data object.
  internal func roundTrip(
    contextTag: UInt8,
    value: Data,
    classByte: UInt8,
    password: borrowing PacePassword
  ) throws -> Data {
    guard
      let template = PaceDataObject.dynamicAuthenticationData(
        contextTag: contextTag,
        value: value
      )
    else {
      throw Failure.malformedResponse
    }
    return try generalAuthenticate(template: template, classByte: classByte, password: password)
  }

  /// Sends one GENERAL AUTHENTICATE and returns its payload.
  ///
  /// With a PIN password a counter answer is a wrong PIN, with the tries
  /// the card reports left (BSI TR-03110-3 section B.14.2).
  internal func generalAuthenticate(
    template: Data,
    classByte: UInt8,
    password: borrowing PacePassword
  ) throws -> Data {
    guard
      let command = PaceCommand.generalAuthenticate(
        template: template,
        classByte: classByte
      )
    else {
      throw Failure.malformedResponse
    }
    let response = try ContinuedResponse.transmitting(command, over: channel)
    switch response.statusWord {
    case .success:
      return response.payload

    case .pinIncorrect(let remaining) where password.credential != nil:
      throw Failure.wrongPin(remaining: remaining)

    default:
      throw Failure.cardRejected(response.statusWord)
    }
  }
}
