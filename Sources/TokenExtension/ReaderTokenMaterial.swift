// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Security

/// Validated material needed to mint one reader-backed token.
internal struct ReaderTokenMaterial {
  /// Certificates and complete card serial read in one card session.
  internal let identity: PublishedIdentity

  /// CAN used when the reader reached the card over contactless.
  internal let accessNumber: CardAccessNumber?

  /// Parsed authentication certificate.
  internal let leaf: SecCertificate

  /// Authentication key profile derived from the certificate.
  internal let profile: CardKeyProfile

  /// Public authentication key used to verify every card signature.
  internal let publicKey: SecKey

  /// Parsed qualified-signature certificate, when the card has one.
  internal let signLeaf: SecCertificate?

  /// Qualified key profile, when the sign leaf resolved to a
  /// supported one.
  internal let signProfile: CardKeyProfile?

  /// Public qualified key used to verify every qualified signature.
  internal let signPublicKey: SecKey?

  /// CryptoTokenKit instance ID derived from the printed serial.
  internal let instanceID: TokenInstanceID
}
