// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Why the custodian ends an operation without an answer.
///
/// Each reason fixes the status and the registered error the result carries
/// (RAPP v26.10.29 §10.3), so a result cannot pair a failure with a status
/// that contradicts it.
internal enum ProxyFailure: Equatable, CaseIterable {
  /// The card returned no answer: no card within the wait, the field lost,
  /// a transmission fault.
  case cardError
  /// The custodian could not carry the operation out for a reason of its
  /// own.
  case operationFailed
  /// The deadline passed before the card was commanded (§8.1 item 2).
  case requestExpired
  /// The request names a parameter this endpoint cannot serve.
  case requestInvalidOrUnsupported
  /// The card reports fewer than three remaining attempts for the PIN; no
  /// verification was sent (§10.2).
  case retryFloor
  /// The pairing did not grant the requested profile (§8.2 item 1).
  case unauthorized
  /// The holder declined on screen (§8.2 item 3).
  case userDenied

  internal var status: ResultStatus {
    switch self {
    case .requestExpired:
      .cancelled

    case .cardError, .operationFailed, .requestInvalidOrUnsupported, .retryFloor, .unauthorized,
      .userDenied:
      .rejected
    }
  }

  internal var error: ResultError {
    switch self {
    case .cardError:
      .cardError

    case .operationFailed:
      .operationFailed

    case .requestExpired:
      .operationExpired

    case .requestInvalidOrUnsupported:
      .unsupportedParameter

    case .retryFloor:
      .retryFloor

    case .unauthorized:
      .unauthorized

    case .userDenied:
      .userCancelled
    }
  }
}
