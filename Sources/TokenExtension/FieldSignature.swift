// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// One signature made through the contactless interface, in the order the
/// field allows.
///
/// Contactless operations use the secure channel established for this powered
/// field. Primed identity material avoids certificate and serial reads during
/// signing. Field loss invalidates the channel and requires a fresh PACE run.
internal struct FieldSignature {
  /// The token this signature belongs to, and the source of everything
  /// the prime already read: the leaf public key and the card serial.
  private let token: Token

  /// The primed card access number PACE opens the card with.
  private let accessNumber: CardAccessNumber

  internal init(token: Token, accessNumber: CardAccessNumber) {
    self.token = token
    self.accessNumber = accessNumber
  }

  /// Probes the PIN1 counter and admits the PIN, or refuses before VERIFY.
  ///
  /// The probe first decides holding (``Pin1Memory/retain(after:serial:)``):
  /// one that forbids it drops the accepted value at once, before any
  /// verdict. The retry floor then refuses a counter it cannot spend. Last,
  /// a value reused from the dropped memory is not sent: the holder is
  /// asked instead. Returns the probe.
  private func admit(
    _ operations: CardOperations,
    origin: AuthorizedPin1.Origin
  ) throws -> RetryProbeOutcome {
    let probe = try operations.probeRetryCounter(role: .pin1)
    let mayHold = Pin1Memory.shared.retain(after: probe, serial: token.chipSerial)
    let verdict = RetryFloor.evaluate(probeOutcome: probe)
    guard verdict == .proceed else {
      TokenLog.error("sign: PIN1 retry floor refuses (\(verdict))")
      throw TokenError.signRefused
    }
    if !mayHold, origin == .acceptedMemory {
      TokenLog.info("sign: PIN1 counter not pristine; reused PIN1 dropped, asking the holder")
      throw TokenError.authenticationRequired
    }
    return probe
  }

  /// Establishes the contactless channel and signs `request` in it.
  ///
  /// The PIN is spent exactly once. There is deliberately no fresh-card
  /// fallback here: once ctkd's field has ended, opening another session
  /// merely waits through `TKError -7` and cannot continue the original
  /// PACE channel. A PACE authentication-token mismatch is cryptographic
  /// proof that the stored CAN cannot open the presented card, so it revokes
  /// this automatic identity rather than leaving a mintable broken token.
  internal func perform(
    pin1: consuming Pin1,
    origin: AuthorizedPin1.Origin,
    request: SignRequest
  ) throws -> Data {
    // Claim the channel for this powered field, preparing it if the hold was
    // passive. A lease serializes the secure-messaging counter across signatures.
    do {
      let lease = try token.heldSession.preparedChannel(accessNumber: accessNumber)
      defer { _ = lease.channel }
      return try sign(in: lease.channel, pin1: pin1, origin: origin, request: request)
    } catch PaceEstablishment.Failure.authenticationTokenMismatch {
      token.revokeAutomaticIdentityAfterCanRejection()
      throw TokenError.primeMissing
    } catch PaceEstablishment.Failure.cardRejected(.authenticationFailed) {
      token.revokeAutomaticIdentityAfterCanRejection()
      throw TokenError.primeMissing
    }
  }

  /// The PIN1 retry floor, VERIFY PIN1 and the on-card signature, inside
  /// the PACE channel.
  ///
  /// Nothing here reads what the prime already knows. The authentication
  /// certificate and the chip serial are public, unchanging and stored
  /// by the prime; re-reading either costs more than the field has left,
  /// and that read was measured dying part way through - not re-reading
  /// them is what turned an intermittent signature into a reliable one.
  /// The certificate is present as the token's cached leaf public key,
  /// which checks the signature below; the serial is present as the
  /// token's chip serial, which PIN 1 memory and the rejected-PIN memory
  /// bind to.
  ///
  /// A probe that does not permit holding (``Pin1Retention``) drops the
  /// accepted value; a value reused from it is then not sent, and the
  /// holder is asked instead.
  private func sign(
    in channel: SecureMessagingChannel,
    pin1: consuming Pin1,
    origin: AuthorizedPin1.Origin,
    request: SignRequest
  ) throws -> Data {
    let operations = CardOperations(channel: channel)
    let serial = token.chipSerial
    let fingerprint = pin1.fingerprint(boundTo: serial)
    if CredentialMemory.rejectedPins.isKnownRejected(fingerprint) {
      throw TokenError.pinAlreadyRejected
    }
    let probe = try admit(operations, origin: origin)
    let acceptance = Pin1Memory.shared.acceptance(of: pin1, serial: serial, after: probe)
    do {
      try operations.verifyPin1(pin1.consumeForSingleTransmission())
    } catch CardOperationError.pinRejected {
      token.forgetPinAfterRefusal(fingerprint: fingerprint)
      throw TokenError.pinRejected
    } catch CardOperationError.pinBlocked {
      token.forgetPinAfterRefusal(fingerprint: fingerprint)
      throw TokenError.signRefused
    } catch {
      // Ambiguous transport or communication failure during or after
      // VERIFY: an unverified candidate is dropped, an accepted value kept.
      Pin1Memory.shared.clearCandidate(serial: serial)
      throw error
    }
    // The card verified the PIN: it is held as accepted when the probe
    // permits holding, and otherwise the candidate is dropped.
    if let acceptance {
      Pin1Memory.shared.commit(acceptance)
    } else {
      Pin1Memory.shared.clearCandidate(serial: serial)
    }
    let raw = try operations.computeAuthenticationSignature(
      overDigest: request.digest,
      algorithm: request.algorithm,
      expectedSignatureLength: request.expectedSignatureLength
    )
    guard
      let signature = request.wireSignature(from: raw),
      request.isSatisfied(by: signature, from: token.leafPublicKey)
    else {
      throw TokenError.signatureMalformed
    }
    return signature
  }
}
