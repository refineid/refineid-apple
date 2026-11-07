// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One certificate the relying party trusts for one role during the
/// periods its status was granted.
///
/// The anchor is the certificate's subject name and public key (RFC
/// 5280 section 6.1.1): a path ends at the first certificate carrying
/// them, for the role the path needs, at a time inside one of the
/// granted periods. Any certificate can be an anchor: a root, an
/// issuing CA a trusted list names, or a time-stamping unit's own
/// certificate.
public struct TrustAnchor: Sendable, Equatable {
  /// What a trust anchor is trusted for.
  public enum Role: Sendable, Equatable {
    /// Issuing the certificates signatures are made under.
    case certificateIssuing

    /// Issuing, or being, the certificates of time-stamping
    /// authorities.
    case timeStamping
  }

  /// The anchor certificate, DER.
  public let certificate: Data

  /// What it is trusted for.
  public let role: Role

  /// When it is trusted; never empty.
  public let granted: [GrantedPeriod]

  /// Trusts `certificate` for `role` during `granted`; nil when
  /// `granted` is empty, since such an anchor would never be trusted.
  public init?(certificate: Data, role: Role, granted: [GrantedPeriod]) {
    guard !granted.isEmpty else { return nil }
    self.certificate = certificate
    self.role = role
    self.granted = granted
  }

  /// Whether this anchor is trusted for `role` at `instant`.
  public func isTrusted(for role: Role, at instant: Date) -> Bool {
    self.role == role && granted.contains { period in period.covers(instant) }
  }
}
