// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// A refused SCS transaction step, as the specification's reason pair.
///
/// The code follows the same classes as the JSON `/sign` path:
/// 400 malformed, 401 credential, 403 policy, 500 internal, 501
/// unimplemented (DVV SCS specification v1.3 §2.6.3).
public struct ScsTransactionError: Error, Equatable, Sendable {
  /// The specification reason code.
  public let code: Int

  /// The human-readable reason.
  public let message: String

  /// A malformed-request refusal.
  public static func badRequest(_ message: String) -> Self {
    Self(code: ScsValues.reasonBadRequest, message: message)
  }

  /// A policy refusal.
  public static func forbidden(_ message: String) -> Self {
    Self(code: ScsValues.reasonForbidden, message: message)
  }

  /// An internal failure.
  public static func internalError(_ message: String) -> Self {
    Self(code: ScsValues.reasonInternalError, message: message)
  }

  /// A valid request for an unimplemented capability.
  public static func notImplemented(_ message: String) -> Self {
    Self(code: ScsValues.reasonNotImplemented, message: message)
  }

  /// Wraps a signing-backend refusal in its specification reason pair;
  /// unexpected internal errors return a constant message rather than
  /// interpolating internal error details to unauthenticated callers.
  internal static func wrapping(_ error: any Error) -> Self {
    guard let failure = error as? ScsBackendFailure else {
      return .internalError("internal signing error")
    }
    return Self(code: failure.reasonCode, message: failure.reasonText)
  }
}
