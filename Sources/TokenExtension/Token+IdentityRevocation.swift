// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore

/// What a PACE failure ends: the token and its stored identity.
extension Token {
  /// Revokes the complete automatic identity after PACE proves that the
  /// stored CAN and the presented card cannot authenticate each other.
  ///
  /// Registration removal is queued off the CTK callback thread to avoid
  /// asking ctkd to unregister a token while ctkd is still executing that
  /// token's sign callback.
  internal func revokeAutomaticIdentityAfterCanRejection() {
    revokeCurrentInstance()
    let representsStoredIdentity: Bool =
      switch interface {
      case .fieldWithDeadline:
        true

      case .contact, .steadyField:
        PrimeStore.contains(serial: chipSerial)
      }
    guard representsStoredIdentity else {
      TokenLog.notice(
        "\(TokenRegistrationRevoker.Reason.canRejection.logPrefix); "
          + "no stored automatic identity belonged to this token")
      return
    }
    CardCredentialStore.forgetCardAccessNumber()
    PrimeStore.forget(serial: chipSerial)
    PrimeStore.clearRegistrationField()
    TokenRegistrationRevoker.revoke(instanceID, reason: .canRejection)
    TokenLog.error(
      "\(TokenRegistrationRevoker.Reason.canRejection.logPrefix); automatic identity revoked")
  }
}
