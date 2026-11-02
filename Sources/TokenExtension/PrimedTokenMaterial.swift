// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Security

/// Validated material needed to mint one contactless token.
internal struct PrimedTokenMaterial {
  /// What opens the card's PACE channel: a personal card's access
  /// number, or an organization card's PIN, which each signature spends.
  internal let unsealing: CardUnsealing

  /// The identity the token publishes, as the prime recorded it.
  internal let identity: PublishedIdentity

  /// Parsed authentication certificate.
  internal let leaf: SecCertificate

  /// Authentication key profile derived from the certificate.
  internal let profile: CardKeyProfile

  /// Public authentication key used to verify every card signature.
  internal let publicKey: SecKey

  /// Chip serial used for security bindings.
  internal let serial: ChipSerial

  /// The CryptoTokenKit instance ID derived from ``serial``.
  internal let instanceID: TokenInstanceID
}
