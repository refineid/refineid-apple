// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Why the custodian ends an operation without an answer.
///
/// Each reason fixes the status and the registered error the result carries,
/// so a result cannot pair a failure with a status that contradicts it.
internal enum ProxyFailure: Equatable {
  /// The session ended before the card was touched.
  case cancelled
  /// The card may have acted; the outcome cannot be known.
  case cardCompletionAmbiguous
  /// The card left before any command was sent.
  case cardRemovedBeforeTransmit
  /// The card reports the credential blocked.
  case credentialRejected
  /// The local deadline passed before approval.
  case requestExpired
  /// The request names a parameter this endpoint cannot serve.
  case requestInvalidOrUnsupported
  /// The retry floor refused the command (section 10.3).
  case retryPolicyRefused
  /// The pairing did not grant the requested profile.
  case unauthorized
  /// The holder declined on screen.
  case userDenied

  internal var status: ResultStatus {
    switch self {
    case .userDenied, .requestInvalidOrUnsupported, .unauthorized, .retryPolicyRefused:
      .rejected

    case .requestExpired, .cancelled, .cardRemovedBeforeTransmit:
      .cancelled

    case .credentialRejected:
      .credentialRejected

    case .cardCompletionAmbiguous:
      .ambiguous
    }
  }

  internal var error: ResultError {
    switch self {
    case .userDenied:
      .userCancelled

    case .requestExpired, .cancelled:
      .operationExpired

    case .requestInvalidOrUnsupported:
      .unsupportedParameter

    case .unauthorized:
      .unauthorized

    case .retryPolicyRefused:
      .operationFailed

    case .credentialRejected:
      .cardBlocked

    case .cardRemovedBeforeTransmit, .cardCompletionAmbiguous:
      .cardError
    }
  }

  /// Whether the endpoint can make no further safe progress on the session.
  internal var closesSession: Bool {
    switch self {
    case .retryPolicyRefused, .credentialRejected, .cardCompletionAmbiguous:
      true

    case .userDenied, .requestExpired, .cancelled, .requestInvalidOrUnsupported, .unauthorized,
      .cardRemovedBeforeTransmit:
      false
    }
  }
}
