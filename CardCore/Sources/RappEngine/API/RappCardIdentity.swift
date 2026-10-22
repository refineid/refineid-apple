// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The `read_identity` answer a requester received (RAPP v26.10.22 §9.1),
/// within the bounds its schema states: built only from a ``CardIdentity``,
/// whose initializer checked them, at least one certificate included.
public struct RappCardIdentity: Equatable, Sendable {
  /// The cardholder's name.
  public let holderName: String
  /// The card identifier.
  public let cardId: String
  /// `YYYY-MM-DD`.
  public let issuanceDate: String
  /// `YYYY-MM-DD`.
  public let expirationDate: String
  /// DER-encoded certificates, at least one.
  public let certificates: [Data]

  internal init(_ identity: CardIdentity) {
    holderName = identity.holderName
    cardId = identity.cardIdentifier
    issuanceDate = identity.issuanceDate
    expirationDate = identity.expirationDate
    certificates = identity.certificates
  }
}
