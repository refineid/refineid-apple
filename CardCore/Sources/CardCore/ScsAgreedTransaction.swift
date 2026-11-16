// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// One agreed SCS transaction awaiting its `execute` (DVV SCS
/// specification v1.3 §2.7).
internal struct ScsAgreedTransaction: Sendable {
  /// The agreed A256GCM transaction key.
  internal let key: SymmetricKey

  /// The Origin that began the transaction; `execute` must match.
  internal let origin: String

  /// The card key the selector chose at `begin`.
  internal let purpose: ScsSignPurpose

  /// The service's base64 agreement key, which the authentication
  /// challenge must be bound to.
  internal let serverKey: String

  /// When `begin` completed, bounding how long the slot remains valid.
  internal let createdAt: Date
}
