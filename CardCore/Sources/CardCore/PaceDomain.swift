// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// A standardized PACE domain parameter this build runs (BSI TR-03110-3
/// table 4).
public enum PaceDomain: Equatable, Sendable, CaseIterable {
  /// brainpoolP384r1 (RFC 5639 section 3.6), identifier 16.
  case brainpoolP384r1

  /// NIST P-256 (`secp256r1`), identifier 12.
  case nistP256

  /// NIST P-384 (`secp384r1`), identifier 15.
  case nistP384

  /// The domains in the order the handshake prefers them.
  ///
  /// The 384-bit curves first, NIST P-384 ahead of brainpoolP384r1, then
  /// P-256 -- the order of the refineid-core reference
  /// (`doc/reference/pace.md`).
  internal static let preference: [Self] = [.nistP384, .brainpoolP384r1, .nistP256]

  /// The standardized domain parameter identifier, as `PACEInfo` lists it
  /// and MSE:Set AT names it (BSI TR-03110-3 section B.14.1).
  internal var parameterID: UInt8 {
    switch self {
    case .nistP256:
      PaceValues.domainParameterReferenceNistP256

    case .nistP384:
      PaceValues.domainParameterReferenceNistP384

    case .brainpoolP384r1:
      PaceValues.domainParameterReferenceBrainpoolP384r1
    }
  }

  /// The domain an identifier names, or nil for one this build does not run.
  internal init?(parameterID: UInt8) {
    guard let domain = Self.allCases.first(where: { $0.parameterID == parameterID }) else {
      return nil
    }
    self = domain
  }
}
