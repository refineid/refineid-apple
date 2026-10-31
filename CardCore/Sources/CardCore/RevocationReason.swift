// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The CRLReason a revocation names (RFC 5280 section 5.3.1), carried
/// by a CRL entry's reasonCode and by an OCSP revokedInfo.
public enum RevocationReason: Sendable, Equatable {
  case affiliationChanged
  case attributeAuthorityCompromise
  case certificateAuthorityCompromise
  case certificateHold
  case cessationOfOperation
  case keyCompromise
  case privilegeWithdrawn
  case removeFromCrl
  case superseded
  /// A code RFC 5280 does not name; judged like `unspecified`.
  case unrecognized
  case unspecified

  /// The CRLReason ENUMERATED values (RFC 5280 section 5.3.1).
  private enum Code {
    static let unspecified = 0
    static let keyCompromise = 1
    static let certificateAuthorityCompromise = 2
    static let affiliationChanged = 3
    static let superseded = 4
    static let cessationOfOperation = 5
    static let certificateHold = 6
    static let removeFromCrl = 8
    static let privilegeWithdrawn = 9
    static let attributeAuthorityCompromise = 10
  }

  /// The RFC 5280 section 5.3.1 code of each named reason.
  private static let codes: [Int: Self] = [
    Code.unspecified: .unspecified,
    Code.keyCompromise: .keyCompromise,
    Code.certificateAuthorityCompromise: .certificateAuthorityCompromise,
    Code.affiliationChanged: .affiliationChanged,
    Code.superseded: .superseded,
    Code.cessationOfOperation: .cessationOfOperation,
    Code.certificateHold: .certificateHold,
    Code.removeFromCrl: .removeFromCrl,
    Code.privilegeWithdrawn: .privilegeWithdrawn,
    Code.attributeAuthorityCompromise: .attributeAuthorityCompromise,
  ]

  /// Whether the reason names a compromised key, which proves nothing
  /// about when the key signed (EN 319 102-1 clause 5.6.2).
  public var isCompromise: Bool {
    switch self {
    case .keyCompromise, .certificateAuthorityCompromise,
      .attributeAuthorityCompromise:
      true

    default:
      false
    }
  }

  /// The reason one CRLReason code names.
  internal init(code: Int) {
    self = Self.codes[code] ?? .unrecognized
  }
}
