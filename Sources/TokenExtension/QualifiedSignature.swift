// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Foundation
import Security

/// One qualified signature taken through a reader.
///
/// The counterpart of ``ReaderSignature`` for the PIN2-gated key, and
/// deliberately poorer in convenience: there is no accepted-PIN memory
/// to reuse and none is written, so every qualified signature costs a
/// fresh PIN2 entry. What it keeps is every safety property - the
/// retry floor before anything irreversible, the rejected-PIN latch so
/// one wrong entry is never resent, and the fail-closed local
/// verification of the card's signature.
///
/// A card-confirmed CAN or PIN2 rejection bankrupts the published token.
/// The extension has no recovery UI; the containing app must explicitly
/// establish a new trusted token before any signing can resume.
internal enum QualifiedSignature {
  /// The sealed channel and the access number that unseals it.
  internal struct ChannelAccess {
    internal let channel: SmartCardChannel
    internal let accessNumber: CardAccessNumber?
  }

  /// Unseals the channel if the card asks for it, then signs in it.
  internal static func perform(
    on access: ChannelAccess,
    enteredPin: String?,
    request: SignRequest,
    signPublicKey: SecKey,
    token: Token
  ) throws -> Data {
    do {
      return try performSign(
        channel: try ReaderSignature.unsealed(access.channel, with: access.accessNumber),
        enteredPin: enteredPin,
        request: request,
        signPublicKey: signPublicKey,
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

  /// The full qualified sign flow, inside the caller's exclusive
  /// session.
  ///
  /// Fully synchronous, on ctkd's thread, like the PIN1 flow.
  private static func performSign(
    channel: any CardChannel,
    enteredPin: String?,
    request: SignRequest,
    signPublicKey: SecKey,
    token: Token
  ) throws -> Data {
    let operations = CardOperations(channel: channel)
    try operations.selectFineidApplication()
    let serial = try Self.probePin2AndReadSerial(operations)

    // PIN2 comes from the prompt or not at all: no cache exists to
    // fall back to, and the throw asks the system to present it.
    guard let entered = enteredPin else {
      throw TokenError.authenticationRequired
    }
    guard let pin2 = Pin2(digits: entered) else {
      throw TokenError.pinFormatInvalid
    }

    let fingerprint = pin2.fingerprint(boundTo: serial)
    guard !CredentialMemory.rejectedPins.isKnownRejected(fingerprint) else {
      TokenLog.error("sign: PIN2 already rejected this session - refusing to resend")
      throw TokenError.pinAlreadyRejected
    }

    TokenLog.info("sign: verifying PIN2")
    do {
      try operations.verifyPin2(pin2.consumeForSingleTransmission())
    } catch CardOperationError.pinRejected {
      token.forgetPinAfterRefusal(fingerprint: fingerprint)
      throw TokenError.pinRejected
    } catch CardOperationError.pinBlocked {
      token.forgetPinAfterRefusal(fingerprint: fingerprint)
      throw TokenError.signRefused
    } catch CardOperationError.credentialInvalidated {
      // A never-activated signature slot: not a wrong PIN, not a card
      // fault - a state the holder resolves through activation.
      TokenLog.error("sign: qualified slot invalidated")
      throw TokenError.signRefused
    }

    TokenLog.info("sign: PIN2 verified; MSE:SET + PSO:HASH + PSO:CDS")
    let raw = try operations.computeQualifiedSignature(
      overDigest: request.digest,
      algorithm: request.algorithm,
      expectedSignatureLength: request.expectedSignatureLength
    )
    guard let signature = request.wireSignature(from: raw) else {
      TokenLog.error("sign: raw qualified signature \(raw.count) bytes has wrong shape")
      throw TokenError.signatureMalformed
    }
    guard request.isSatisfied(by: signature, from: signPublicKey) else {
      TokenLog.error("sign: local verify FAILED - card returned a bad qualified signature")
      throw TokenError.signatureMalformed
    }
    TokenLog.info("sign: local verify OK, \(signature.count) wire bytes")
    return signature
  }

  /// Reads only the retry state of the credential this operation
  /// spends: PIN2, and nothing else.
  private static func probePin2AndReadSerial(
    _ operations: CardOperations
  ) throws -> TokenSerial {
    TokenLog.info("sign: PIN2 retry-floor probe")
    let outcome = try operations.probeRetryCounter(role: .pin2)
    let verdict = RetryFloor.evaluate(probeOutcome: outcome)
    guard verdict == .proceed else {
      TokenLog.error("sign: PIN2 retry floor refuses (\(verdict)); pin2=\(outcome)")
      throw TokenError.signRefused
    }
    return try operations.readTokenSerial()
  }
}
