// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Why the signing backend refused an SCS sign.
///
/// The protocol maps these to the specification's reason codes: a
/// credential refusal answers 401, a rate-limit or policy refusal 403,
/// and card or reader unavailability 500 (DVV SCS specification v1.3
/// §2.6.3). The text never carries a credential, retry count, or card
/// serial.
public enum ScsBackendFailure: Error, Equatable, Sendable {
  /// The credential was refused, missing, or cancelled.
  case credentialRefused(String)

  /// Local rate-limiting or prompt policy refused the request.
  case policyRefused(String)

  /// The card, reader, or sign chain failed.
  case signingUnavailable(String)

  /// The specification reason code for this failure.
  internal var reasonCode: Int {
    switch self {
    case .credentialRefused:
      ScsValues.reasonUnauthorized

    case .policyRefused:
      ScsValues.reasonForbidden

    case .signingUnavailable:
      ScsValues.reasonInternalError
    }
  }

  /// The reason-text prefix plus detail for this failure.
  internal var reasonText: String {
    switch self {
    case .credentialRefused(let detail):
      "Unauthorized: " + detail

    case .policyRefused(let detail):
      "Forbidden: " + detail

    case .signingUnavailable(let detail):
      "Internal Server Error: " + detail
    }
  }
}
