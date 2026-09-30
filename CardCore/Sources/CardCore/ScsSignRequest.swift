// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One signature the SCS has been asked to produce.
///
/// The payload, the key that signs it, and the origin that asked are
/// bound together because the end user has to be told all three before
/// a PIN is asked for: which site wants a signature, and what it is
/// about to sign (DVV SCS specification v1.3 §2.1). Carrying the
/// origin here rather than passing it alongside keeps the two from
/// being confused at a call site that signs a derived payload.
public struct ScsSignRequest: Sendable {
  /// The key the sign uses.
  public let purpose: ScsSignPurpose

  /// The hash applied to `data` before the card signs the digest.
  public let hash: SigningHash

  /// The bytes to be signed.
  public let data: Data

  /// The Origin header of the request that asked, or nil when the
  /// request carried none.
  public let origin: String?

  /// Composes a sign to perform.
  public init(
    purpose: ScsSignPurpose,
    hash: SigningHash,
    data: Data,
    origin: String?
  ) {
    self.purpose = purpose
    self.hash = hash
    self.data = data
    self.origin = origin
  }
}
