// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The revocation status validation evidence establishes for one
/// signer (EN 319 102-1 clause 5.2.6).
public enum RevocationState: Sendable, Equatable {
  /// A verified answer says good; the date is the evidence time, the
  /// OCSP producedAt or the CRL thisUpdate.
  case good(Date)

  /// A verified answer says revoked at the date, for the reason when
  /// the evidence names one.
  case revoked(Date, RevocationReason?)

  /// No verified answer speaks for the validation time.
  case unavailable

  /// Whether the revocation invalidates a signature proven to exist
  /// at `proofOfExistence`: a revocation at or before it, any
  /// revocation without a proof, and a compromise whatever its time
  /// (EN 319 102-1 clause 5.6.2).
  public func invalidates(proofOfExistence: Date?) -> Bool {
    guard case .revoked(let revokedAt, let reason) = self else { return false }
    if reason?.isCompromise == true { return true }
    guard let proofOfExistence else { return true }
    return revokedAt <= proofOfExistence
  }
}
