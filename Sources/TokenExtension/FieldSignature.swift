// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// One signature made through the contactless interface, in the order the
/// field allows.
///
/// A contactless card seals its PKCS#15 application until PACE has run,
/// so everything here travels inside the secure-messaging channel PACE
/// yields. What shapes the rest is time: on the system-driven path `ctkd`
/// owns the slot and ends it about two seconds after the token is minted,
/// so this reads nothing the prime already knows, spends no APDU on
/// diagnostics, and writes no log line at all - a single probe APDU at
/// the head of this path was measured costing the whole handshake.
///
/// Provenance: the contactless branch of the donor
/// `platform/apple/RefineIDTokenExtension/TokenSession.swift`, whose
/// transport was a Rust FFI relay; here it is CardCore's own PACE,
/// secure messaging and card operations.
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

  /// Establishes the contactless channel and signs `request` in it.
  ///
  /// The PIN is spent exactly once. There is deliberately no fresh-card
  /// fallback here: once ctkd's field has ended, opening another session
  /// merely waits through `TKError -7` and cannot continue the original
  /// PACE channel. A PACE authentication-token mismatch is cryptographic
  /// proof that the stored CAN cannot open the presented card, so it revokes
  /// this automatic identity rather than leaving a mintable broken token.
  internal func perform(pin1: consuming Pin1, request: SignRequest) throws -> Data {
    // The mint starts PACE immediately on a worker and retains that exact
    // secure channel. This keeps the expensive work ahead of Safari's
    // later sign callback and keeps its mutable counter for a second
    // signature from the same token.
    do {
      let lease = try token.heldSession.preparedChannel(accessNumber: accessNumber)
      defer { _ = lease.channel }
      return try sign(in: lease.channel, pin1: pin1, request: request)
    } catch PaceEstablishment.Failure.authenticationTokenMismatch {
      token.revokeAutomaticIdentityAfterCanRejection()
      throw TokenError.primeMissing
    } catch PaceEstablishment.Failure.cardRejected(.authenticationFailed) {
      token.revokeAutomaticIdentityAfterCanRejection()
      throw TokenError.primeMissing
    }
  }

  /// VERIFY PIN1 and the on-card signature, inside the PACE channel.
  ///
  /// Nothing here reads what the prime already knows. The authentication
  /// certificate and the token serial are public, unchanging and stored
  /// by the prime; re-reading either costs more than the field has left,
  /// and that read was measured dying part way through - not re-reading
  /// them is what turned an intermittent signature into a reliable one.
  /// The certificate is present as the token's cached leaf public key,
  /// which checks the signature below; the serial is present as the
  /// cached serial the rejected-PIN memory binds to.
  private func sign(
    in channel: SecureMessagingChannel,
    pin1: consuming Pin1,
    request: SignRequest
  ) throws -> Data {
    let operations = CardOperations(channel: channel)
    let fingerprint: PinFingerprint?
    if let serial = token.primedSerial {
      fingerprint = pin1.fingerprint(boundTo: serial)
    } else {
      fingerprint = nil
    }
    if let fingerprint, CredentialMemory.rejectedPins.isKnownRejected(fingerprint) {
      throw TokenError.pinAlreadyRejected
    }
    let pendingAcceptance: VolatileAcceptedPin1.PendingAcceptance?
    if OnDemandPinExperiment.isEnabled {
      pendingAcceptance = VolatileAcceptedPin1.shared.prepareAcceptance(
        of: pin1,
        for: token.cardInstanceID
      )
    } else {
      pendingAcceptance = nil
    }
    do {
      try operations.verifyPin1(pin1.consumeForSingleTransmission())
    } catch CardOperationError.pinRejected, CardOperationError.pinBlocked {
      TransientCandidatePin1.shared.clear(for: token.cardInstanceID)
      VolatileAcceptedPin1.shared.clear(for: token.cardInstanceID)
      if let serial = token.primedSerial, let fingerprint {
        token.revokeAutomaticIdentityAfterPin1Rejection(
          serial: serial,
          fingerprint: fingerprint)
      }
      throw TokenError.pinRejected
    } catch {
      // Ambiguous transport/communication failure during or after VERIFY transmission:
      // clear unverified candidate store, but preserve previously accepted memory.
      if !VolatileAcceptedPin1.shared.hasPin(for: token.cardInstanceID) {
        TransientCandidatePin1.shared.clear(for: token.cardInstanceID)
      }
      throw error
    }
    // VERIFY succeeded on the physical card: promote to accepted memory and clear candidate.
    TransientCandidatePin1.shared.clear(for: token.cardInstanceID)
    pendingAcceptance?.commit()
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
