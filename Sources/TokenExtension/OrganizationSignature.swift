// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Foundation
import Security

/// One signature by an organization card on a reader's antenna.
///
/// The card's contactless channel opens only with PACE and a PIN as the
/// password (FINEID S1 v4.0, organizational cards, section 2.1): PIN 1 for
/// the authentication key, PIN 2 for the qualified key. A completed PACE
/// counts as that PIN verified, so the key signs with no VERIFY, and no
/// VERIFY status probe is sent inside the channel, which the card refuses
/// there (`6988`, observed on hardware). The retry floor is applied
/// instead to the PIN's state MSE:Set AT reports, before the first
/// GENERAL AUTHENTICATE: the card takes a try at that command and gives
/// it back only when the handshake completes.
///
/// So the PIN is settled first -- typed in the system sheet, or the PIN 1
/// this card accepted before -- and only then is the card touched. Every
/// signature opens its own channel; PIN 1 accepted once is reused for the
/// next one while ``Pin1Retention`` permits it, exactly as on the contact
/// path.
internal enum OrganizationSignature {
  /// An authentication signature with the PIN 1-gated key.
  internal static func authenticate(
    on channel: SmartCardChannel,
    enteredPin: String?,
    request: SignRequest,
    token: Token
  ) throws -> Data {
    let serial = token.chipSerial
    let pin1 = try ReaderSignature.pin(entered: enteredPin, serial: serial)
    let fingerprint = pin1.fingerprint(boundTo: serial)
    guard !CredentialMemory.rejectedPins.isKnownRejected(fingerprint) else {
      TokenLog.error("sign: PIN already rejected this session - refusing to resend")
      throw TokenError.pinAlreadyRejected
    }
    let (operations, pinState) = try opened(
      channel,
      password: PacePassword(pin1: pin1.consumeForSingleTransmission()),
      pin: .pin1,
      fingerprint: fingerprint,
      token: token
    )
    try operations.selectFineidApplication()
    guard try operations.readChipSerial() == serial else {
      TokenLog.error("sign: card in the slot is not the token's card")
      throw TokenError.signRefused
    }
    TokenLog.info("sign: PIN 1 opened the channel; MSE:SET + PSO:CDS")
    let raw = try operations.computeAuthenticationSignature(
      overDigest: request.digest,
      algorithm: request.algorithm,
      expectedSignatureLength: request.expectedSignatureLength
    )
    let signature = try ReaderSignature.checkedWireSignature(
      from: raw, request: request, token: token)
    ReaderSignature.rememberOnSuccess(enteredPin: enteredPin, token: token, probe: pinState)
    return signature
  }

  /// A qualified signature with the PIN 2-gated key.
  ///
  /// After PACE with PIN 2 the card signs in DF.ESIGN, selected by its
  /// name from the main file (FINEID S4-2 v4.0 section 4.6.21), under the
  /// organization qualified key reference with the digest inline in one
  /// PSO:CDS (Idemia organizational cards specification section 6.6.2.3).
  /// PIN 2 is never held: every qualified signature is one entry.
  internal static func qualified(
    on channel: SmartCardChannel,
    enteredPin: String?,
    request: SignRequest,
    signPublicKey: SecKey,
    token: Token
  ) throws -> Data {
    guard let entered = enteredPin else {
      throw TokenError.authenticationRequired
    }
    guard let pin2 = Pin2(digits: entered) else {
      throw TokenError.pinFormatInvalid
    }
    let fingerprint = pin2.fingerprint(boundTo: token.chipSerial)
    guard !CredentialMemory.rejectedPins.isKnownRejected(fingerprint) else {
      TokenLog.error("sign: PIN2 already rejected this session - refusing to resend")
      throw TokenError.pinAlreadyRejected
    }
    let (operations, _) = try opened(
      channel,
      password: PacePassword(pin2: pin2.consumeForSingleTransmission()),
      pin: .pin2,
      fingerprint: fingerprint,
      token: token
    )
    try operations.selectEsignDirectory()
    TokenLog.info("sign: PIN 2 opened the channel; MSE:SET + PSO:CDS in DF.ESIGN")
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

  /// Opens the secure channel with `password`, answering every refusal
  /// as the PIN sheet expects.
  ///
  /// A floor refusal, a deactivated PIN and a blocked one refuse the
  /// signature; a wrong PIN is remembered so it is never sent again, and
  /// the PINs this token holds go. PIN 1's state also decides whether an
  /// accepted PIN 1 may still be held.
  private static func opened(
    _ channel: SmartCardChannel,
    password: consuming PacePassword,
    pin role: CredentialRole,
    fingerprint: PinFingerprint,
    token: Token
  ) throws -> (operations: CardOperations, pinState: RetryProbeOutcome) {
    let started = ContinuousClock.now
    let established: PaceEstablishment.Established
    do {
      established = try PaceEstablishment(channel: channel).establish(with: password)
    } catch PaceEstablishment.Failure.retryFloorRefused(let verdict, let state) {
      if role == .pin1 {
        Pin1Memory.shared.retain(after: state, serial: token.chipSerial)
      }
      TokenLog.error("sign: \(role) retry floor refuses (\(verdict)); state=\(state)")
      throw TokenError.signRefused
    } catch PaceEstablishment.Failure.passwordDeactivated {
      TokenLog.error("sign: \(role) deactivated")
      throw TokenError.signRefused
    } catch PaceEstablishment.Failure.wrongPin(let remaining) {
      token.forgetPinAfterRefusal(fingerprint: fingerprint)
      throw remaining.isBlocked ? TokenError.signRefused : TokenError.pinRejected
    }
    TokenLog.info(
      "sign: PACE with \(role) ok ms="
        + TraceTiming.milliseconds(started.duration(to: ContinuousClock.now))
    )
    guard let pinState = established.pinState else {
      throw TokenError.signRefused
    }
    if role == .pin1 {
      Pin1Memory.shared.retain(after: pinState, serial: token.chipSerial)
    }
    let secure = SecureMessagingChannel(wrapping: channel, sessionKeys: established.keys)
    return (CardOperations(channel: secure, openedWith: role), pinState)
  }
}
