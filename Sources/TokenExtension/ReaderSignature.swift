// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Foundation
import Security

/// One signature taken through a reader, contact or contactless.
///
/// The counterpart of ``FieldSignature``, and the difference between
/// them is time rather than secrecy. Both may run inside a PACE channel;
/// only this one can afford to look at the card first. A reader holds
/// its field for as long as the work takes, so a signature here reads the
/// serial and PIN1 retry counter before it does anything irreversible.
/// PIN2 and PUK are unrelated to authentication and stay off this path.
/// A PIN the card accepts is kept on this token and reused until the
/// card or reader leaves, while the card's PIN1 counter stays at its
/// full allowance (``Pin1Retention``).
///
/// A card held against a phone gets none of that: the system ends the
/// slot about two seconds after the mint, so ``FieldSignature`` asks for
/// the PIN before touching the card and reads nothing it was not
/// already given.
internal enum ReaderSignature {
  /// Unseals the channel if the card asks for it, then signs in it.
  internal static func perform(
    in channel: SmartCardChannel,
    unsealingWith accessNumber: CardAccessNumber?,
    enteredPin: String?,
    request: SignRequest,
    token: Token
  ) throws -> Data {
    do {
      return try performSign(
        channel: try unsealed(channel, with: accessNumber),
        enteredPin: enteredPin,
        request: request,
        token: token
      )
    } catch PaceEstablishment.Failure.authenticationTokenMismatch {
      token.revokeAutomaticIdentityAfterCanRejection()
      throw TokenError.primeMissing
    } catch PaceEstablishment.Failure.cardRejected(.authenticationFailed) {
      token.revokeAutomaticIdentityAfterCanRejection()
      throw TokenError.primeMissing
    }
  }

  /// The channel to work in: the plain one for a contact card, or a
  /// secure-messaging one for a card on an antenna.
  ///
  /// PACE has to start at main-file level -- the card refuses MSE:Set
  /// AT with 6985 anywhere else -- and the select is best effort, as
  /// everywhere else this runs: PACE is the step whose failure is worth
  /// reporting. Internal, not private: ``QualifiedSignature`` unseals
  /// the same way.
  internal static func unsealed(
    _ channel: SmartCardChannel,
    with accessNumber: CardAccessNumber?
  ) throws -> any CardChannel {
    guard let accessNumber else { return channel }
    let started = ContinuousClock.now
    try? CardOperations(channel: channel).selectMainFile()
    let keys = try PaceEstablishment(channel: channel).establish(with: accessNumber)
    TokenLog.info(
      "sign: PACE ok ms="
        + TraceTiming.milliseconds(started.duration(to: ContinuousClock.now))
    )
    return SecureMessagingChannel(wrapping: channel, sessionKeys: keys)
  }

  /// The PIN to spend: freshly entered, or reused from the card-bound
  /// memory, or none -- in which case the system is asked to prompt.
  ///
  /// Accepted-PIN memory is bound to the full card serial and lives only
  /// on this token, never in storage (RAPP v26.10.22 §11 item 2); a miss
  /// asks the holder again.
  private static func pin(
    entered: String?,
    serial: TokenSerial,
    token: Token
  ) throws -> Pin1 {
    if let entered {
      guard let built = Pin1(digits: entered) else {
        throw TokenError.pinFormatInvalid
      }
      return built
    }
    if let cached = token.acceptedPin1.checkout(serial: serial) {
      TokenLog.info("sign: reusing accepted PIN1 - no prompt")
      return cached
    }
    throw TokenError.authenticationRequired
  }

  /// The full contact sign flow, inside the caller's exclusive session.
  ///
  /// Fully synchronous: CTK calls `sign` on ctkd's own thread and the card
  /// is a blocking device, so the whole chain runs straight through with no
  /// `Task`/`await` (the async bridge hung here). Mirrors the reference.
  private static func performSign(
    channel: any CardChannel,
    enteredPin: String?,
    request: SignRequest,
    token: Token
  ) throws -> Data {
    let operations = CardOperations(channel: channel)
    try operations.selectFineidApplication()
    let (serial, pin1Outcome) = try Self.probePin1AndReadSerial(operations)
    if !Pin1Retention.permitsHolding(after: pin1Outcome) {
      token.acceptedPin1.clear(serial: serial)
    }

    let raw: Data
    // A card already verified in this session signs without another VERIFY
    // when this token holds the PIN it accepted (FINEID S1 v4.2 section 3.5).
    // A PIN the holder typed is always tested against the card.
    if enteredPin == nil,
      pin1Outcome == .verified,
      let cachedPin = token.acceptedPin1.checkout(serial: serial)
    {
      do {
        TokenLog.info("sign: session already verified; skipping redundant VERIFY PIN1")
        raw = try operations.computeAuthenticationSignature(
          overDigest: request.digest,
          algorithm: request.algorithm,
          expectedSignatureLength: request.expectedSignatureLength
        )
      } catch CardOperationError.signRejected(let statusWord)
        where statusWord == .securityNotSatisfied
      {
        TokenLog.info("sign: card reported security not satisfied; falling back to VERIFY PIN1")
        raw = try Self.verifyAndComputeSignature(
          operations: operations,
          pin1: cachedPin,
          serial: serial,
          request: request,
          token: token
        )
      }
    } else {
      let pin1 = try Self.pin(entered: enteredPin, serial: serial, token: token)
      raw = try Self.verifyAndComputeSignature(
        operations: operations,
        pin1: pin1,
        serial: serial,
        request: request,
        token: token
      )
    }

    let signature = try Self.checkedWireSignature(from: raw, request: request, token: token)
    Self.rememberOnSuccess(
      enteredPin: enteredPin, serial: serial, probe: pin1Outcome, token: token)
    return signature
  }

  /// The wire form of the card's raw signature, checked against the leaf
  /// public key before anything is remembered or returned.
  private static func checkedWireSignature(
    from raw: Data,
    request: SignRequest,
    token: Token
  ) throws -> Data {
    guard let signature = request.wireSignature(from: raw) else {
      TokenLog.error("sign: raw signature \(raw.count) bytes has wrong shape")
      throw TokenError.signatureMalformed
    }
    guard request.isSatisfied(by: signature, from: token.leafPublicKey) else {
      TokenLog.error("sign: local verify FAILED - card returned a bad signature")
      throw TokenError.signatureMalformed
    }
    TokenLog.info("sign: local verify OK, \(signature.count) wire bytes")
    return signature
  }

  /// Verifies PIN1 on card and computes the authentication signature.
  private static func verifyAndComputeSignature(
    operations: CardOperations,
    pin1: consuming Pin1,
    serial: TokenSerial,
    request: SignRequest,
    token: Token
  ) throws -> Data {
    let fingerprint = pin1.fingerprint(boundTo: serial)
    guard !CredentialMemory.rejectedPins.isKnownRejected(fingerprint) else {
      TokenLog.error("sign: PIN already rejected this session - refusing to resend")
      throw TokenError.pinAlreadyRejected
    }

    TokenLog.info("sign: verifying PIN1")
    do {
      try operations.verifyPin1(pin1.consumeForSingleTransmission())
    } catch CardOperationError.pinRejected {
      token.endInstanceAfterPinRejection(
        serial: serial,
        fingerprint: fingerprint)
      throw TokenError.pinRejected
    } catch CardOperationError.pinBlocked {
      token.endInstanceAfterPinRejection(
        serial: serial,
        fingerprint: fingerprint)
      throw TokenError.pinRejected
    }

    TokenLog.info("sign: PIN1 verified; MSE:SET + PSO:HASH + PSO:CDS")
    return try operations.computeAuthenticationSignature(
      overDigest: request.digest,
      algorithm: request.algorithm,
      expectedSignatureLength: request.expectedSignatureLength
    )
  }

  /// Reads only the retry state of the credential this operation spends.
  ///
  /// PIN2 is used for qualified signatures and PUK for recovery. Reading
  /// either during authentication adds APDUs and unrelated failure modes
  /// without protecting PIN1.
  private static func probePin1AndReadSerial(
    _ operations: CardOperations
  ) throws -> (serial: TokenSerial, outcome: RetryProbeOutcome) {
    TokenLog.info("sign: PIN1 retry-floor probe")
    let outcome = try operations.probeRetryCounter(role: .pin1)
    let verdict = RetryFloor.evaluate(probeOutcome: outcome)
    guard verdict == .proceed else {
      TokenLog.error(
        "sign: PIN1 retry floor refuses (\(verdict)); pin1=\(outcome)"
      )
      throw TokenError.signRefused
    }
    let serial = try operations.readTokenSerial()
    return (serial, outcome)
  }

  /// Remembers a freshly entered PIN only after the card accepted it, and
  /// only when the probe before it permits holding (``Pin1Retention``).
  private static func rememberOnSuccess(
    enteredPin: String?,
    serial: TokenSerial,
    probe: RetryProbeOutcome,
    token: Token
  ) {
    guard Pin1Retention.permitsHolding(after: probe) else { return }
    if let entered = enteredPin, let accepted = Pin1(digits: entered) {
      token.acceptedPin1.store(accepted, serial: serial)
    }
  }
}
