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
/// next one only while MSE:Set AT reports no refusal since the card
/// accepted it, and a PIN 1 the card refuses is dropped at once
/// (``OrganizationCardOpening/pin1(over:entered:serial:records:)``).
internal enum OrganizationSignature {
  /// An authentication signature with the PIN 1-gated key.
  internal static func authenticate(
    on channel: SmartCardChannel,
    enteredPin: String?,
    request: SignRequest,
    token: Token
  ) throws -> Data {
    let opening: OrganizationCardOpening.Pin1Opening
    do {
      opening = try OrganizationCardOpening.pin1(
        over: channel,
        entered: try Self.typedPin1(enteredPin),
        serial: token.chipSerial,
        records: OrganizationCardOpening.Pin1Records(
          memory: Pin1Memory.shared,
          rejected: CredentialMemory.rejectedPins,
          owner: token.pin1Owner)
      )
    } catch OrganizationCardOpening.Pin1Unsettled.entryRequired {
      TokenLog.info("sign: PIN 1 entry required")
      throw TokenError.authenticationRequired
    } catch OrganizationCardOpening.Pin1Unsettled.knownRejected {
      TokenLog.error("sign: PIN already rejected this session - refusing to resend")
      throw TokenError.pinAlreadyRejected
    } catch let failure as PaceEstablishment.Failure {
      throw Self.refusal(failure, pin: .pin1)
    }
    let operations = opening.opened.operations
    let serial = token.chipSerial
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
    if let acceptance = opening.acceptance {
      Pin1Memory.shared.commit(acceptance, after: opening.opened.pinState)
    }
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
    let operations: CardOperations
    do {
      operations = try OrganizationCardOpening.pin2(
        over: channel, pin2.consumeForSingleTransmission()
      ).operations
    } catch let failure as PaceEstablishment.Failure {
      if case .wrongPin = failure {
        token.forgetPinAfterRefusal(fingerprint: fingerprint)
      }
      throw Self.refusal(failure, pin: .pin2)
    }
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

  /// The PIN 1 the holder typed, or nil when none was.
  private static func typedPin1(_ digits: String?) throws -> Pin1? {
    guard let digits else { return nil }
    guard let pin = Pin1(digits: digits) else {
      throw TokenError.pinFormatInvalid
    }
    return pin
  }

  /// The error the PIN sheet expects for a handshake the card refused.
  ///
  /// A floor refusal, a deactivated PIN and a blocked one refuse the
  /// signature; a wrong PIN asks again. Every other failure is passed on.
  internal static func refusal(_ failure: PaceEstablishment.Failure, pin role: CredentialRole)
    -> any Error
  {
    switch failure {
    case .retryFloorRefused(let verdict, let state):
      TokenLog.error("sign: \(role) retry floor refuses (\(verdict)); state=\(state)")
      return TokenError.signRefused

    case .passwordDeactivated:
      TokenLog.error("sign: \(role) deactivated")
      return TokenError.signRefused

    case .wrongPin(let remaining):
      TokenLog.error("sign: \(role) refused by the card")
      return remaining.isBlocked ? TokenError.signRefused : TokenError.pinRejected

    default:
      TokenLog.error("sign: PACE with \(role) failed: \(failure)")
      return failure
    }
  }
}
