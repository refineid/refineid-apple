// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One signature the SCS has been asked to produce.
///
/// The payload, the key that signs it, and the origin that asked are
/// bound together because the holder must be shown the requesting
/// origin and the SHA-256 fingerprint of the exact to-be-signed bytes
/// before entering a PIN (DVV SCS specification v1.3 §2.1, §3.7).
public struct ScsSignRequest: Sendable {
  /// The key the sign uses.
  public let purpose: ScsSignPurpose

  /// The hash applied to `data` before the card signs the digest.
  public let hash: SigningHash

  /// The exact bytes to be hashed and signed by the card.
  public let data: Data

  /// The Origin header of the request that asked, or nil when the
  /// request carried none.
  public let origin: String?

  /// Optional document digest to display in the consent prompt
  /// when the payload to be signed by the card is a CMS container
  /// rather than raw document data.
  public let consentDigest: Data?

  /// Lowercase hexadecimal SHA-256 fingerprint for the consent prompt.
  public var sha256Hex: String {
    if let consentDigest {
      return ScsConsentDetails.sha256Hex(of: consentDigest)
    }
    return ScsConsentDetails.sha256Hex(of: data)
  }

  /// Composes a sign to perform.
  public init(
    purpose: ScsSignPurpose,
    hash: SigningHash,
    data: Data,
    origin: String?
  ) {
    self.init(
      purpose: purpose,
      hash: hash,
      data: data,
      origin: origin,
      consentDigest: nil
    )
  }

  /// Composes a sign to perform with an explicit consent document digest.
  public init(
    purpose: ScsSignPurpose,
    hash: SigningHash,
    data: Data,
    origin: String?,
    consentDigest: Data?
  ) {
    self.purpose = purpose
    self.hash = hash
    self.data = data
    self.origin = origin
    self.consentDigest = consentDigest
  }
}
