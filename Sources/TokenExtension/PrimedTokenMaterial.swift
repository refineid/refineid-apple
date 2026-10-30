// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Security

/// Validated material needed to mint one contactless token.
internal struct PrimedTokenMaterial {
  /// CAN that opens the card's PACE channel.
  internal let accessNumber: CardAccessNumber

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
