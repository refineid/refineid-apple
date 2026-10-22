// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore

/// What a confirmed refusal by the card ends.
extension Token {
  /// Ends this token instance after the card refused a PIN the holder
  /// typed.
  ///
  /// The PIN memory goes and the refused value is remembered so it is never
  /// sent again; the stored identity stays, because a PIN is never stored
  /// and the card the phone holds has not left it (RAPP v26.10.22 §8.4 item
  /// 1, §11 item 2). Transport loss, PACE failure, malformed signatures and
  /// TLS errors do not come here; only the card's VERIFY response does.
  internal func endInstanceAfterPinRejection(
    serial: TokenSerial,
    fingerprint: PinFingerprint
  ) {
    revokeCurrentInstance()
    CredentialMemory.rejectedPins.recordRejection(fingerprint)
    acceptedPin1.clear(serial: serial)
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
