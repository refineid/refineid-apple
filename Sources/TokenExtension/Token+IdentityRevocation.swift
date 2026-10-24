// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore

/// What a confirmed refusal by the card ends.
extension Token {
  /// Forgets a PIN the card refused, and keeps the token.
  ///
  /// The refused value is remembered so it is never sent again, and every
  /// held PIN of this token goes; the token itself stays live, so the
  /// system's next prompt reaches a card that can still answer, and the
  /// retry floor decides from the counter whether an attempt may be sent
  /// at all. The stored identity stays, because a PIN is never stored and
  /// the card has not left (RAPP v26.10.22 section 8.4 item 1, section 11
  /// item 2). Transport loss, PACE failure, malformed signatures and TLS
  /// errors do not come here; only the card's VERIFY response does.
  internal func forgetPinAfterRefusal(fingerprint: PinFingerprint) {
    CredentialMemory.rejectedPins.recordRejection(fingerprint)
    acceptedPin1.clearAll()
    VolatileAcceptedPin1.shared.clear(for: cardInstanceID)
    TransientCandidatePin1.shared.clear(for: cardInstanceID)
  }

  /// Revokes the complete automatic identity after PACE proves that the
  /// stored CAN and the presented card cannot authenticate each other.
  ///
  /// Registration removal is queued off the CTK callback thread to avoid
  /// asking ctkd to unregister a token while ctkd is still executing that
  /// token's sign callback.
  internal func revokeAutomaticIdentityAfterCanRejection() {
    revokeCurrentInstance()
    if let serial = primedSerial {
      acceptedPin1.clear(serial: serial)
    }
    let representsStoredIdentity: Bool =
      switch interface {
      case .fieldWithDeadline:
        true

      case .contact, .steadyField:
        PrimeStore.contains(instanceID: cardInstanceID)
      }
    guard representsStoredIdentity else {
      TokenLog.notice(
        "\(TokenRegistrationRevoker.Reason.canRejection.logPrefix); "
          + "no stored automatic identity belonged to this token")
      return
    }
    CardCredentialStore.forgetCardAccessNumber()
    PrimeStore.forget(instanceID: cardInstanceID)
    PrimeStore.clearRegistrationField()
    TokenRegistrationRevoker.revoke(cardInstanceID, reason: .canRejection)
    TokenLog.error(
      "\(TokenRegistrationRevoker.Reason.canRejection.logPrefix); automatic identity revoked")
  }
}
