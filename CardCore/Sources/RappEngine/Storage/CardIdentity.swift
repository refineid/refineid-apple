// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The `read_identity` answer (RAPP v26.10.9 §9.1).
internal struct CardIdentity: Equatable {
  /// Byte bounds the response schema fixes.
  internal enum Bounds {
    internal static let holderName = 1...128
    internal static let cardIdentifier = 1...64
    internal static let date = 10...10
    internal static let tokenDisplayName = 1...64
  }

  internal var holderName: String
  internal var cardIdentifier: String
  /// `YYYY-MM-DD`.
  internal var issuanceDate: String
  /// `YYYY-MM-DD`.
  internal var expirationDate: String
  /// DER-encoded X.509 certificates, at least one.
  internal var certificates: [Data]
  internal var tokenDisplayName: String?

  internal func validate() throws {
    guard Bounds.holderName.contains(holderName.utf8.count),
      Bounds.cardIdentifier.contains(cardIdentifier.utf8.count),
      Bounds.date.contains(issuanceDate.utf8.count),
      Bounds.date.contains(expirationDate.utf8.count),
      !certificates.isEmpty,
      certificates.allSatisfy({ !$0.isEmpty }),
      tokenDisplayName.map({ Bounds.tokenDisplayName.contains($0.utf8.count) }) ?? true
    else { throw CardOperationError.invalidField(field: "response") }
  }
}
