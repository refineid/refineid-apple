// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Typed failures of card operations.
///
/// Transport-layer errors (reader gone, card pulled) propagate as the
/// channel's own thrown errors; these cases are protocol-level: the
/// card answered, and the answer was wrong.
public enum CardOperationError: Error, Equatable, Sendable {
  /// The credential slot is invalidated (`6984`): its usage or
  /// unblocking allowance is exhausted, or the slot has not been
  /// activated.
  case credentialInvalidated

  /// A credential change or unblock was refused with a status word
  /// outside the modelled outcomes.
  case credentialUpdateFailed(StatusWord)

  /// An exchange ended with neither a reply nor an error: the session no
  /// longer reaches the card.
  case exchangeUnanswered

  /// A response was shorter than a status word or beyond the
  /// short-form bound.
  case malformedResponse

  /// The presented credential was refused because it is blocked.
  case pinBlocked

  /// An entry's length is outside what the card in session accepts for
  /// `role`; nothing carrying it was sent.
  case pinLengthRefused(CredentialRole)

  /// The presented credential was rejected; `remaining` attempts are
  /// left before it locks.
  case pinRejected(remaining: RetryCount)

  /// VERIFY returned an unexpected status word.
  case pinVerifyFailed(StatusWord)

  /// A file read failed with the carried typed reason.
  case readFailed(BinaryReadFailure)

  /// A SELECT was answered with something other than success.
  case selectRejected(StatusWord)

  /// An exclusive card session could not be opened.
  case sessionUnavailable

  /// A signing command (MSE:SET or PSO:CDS) was refused.
  case signRejected(StatusWord)

  /// EF.TokenInfo was read but its content did not parse to a serial.
  case tokenInfoMalformed
}
