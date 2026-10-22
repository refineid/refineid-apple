// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// The SHA-256 digest of the DER encoding of a card's authentication
/// certificate (RAPP v26.10.21 §8.4 item 2), naming which card the custodian
/// serves.
public struct RappCertificateFingerprint: Hashable, Sendable {
  /// Byte length of a SHA-256 digest (§7.1 `bstr .size 32`).
  internal static let byteCount = SHA256.byteCount

  internal let digest: Data

  /// The fingerprint of `certificate`, the DER encoding of an
  /// authentication certificate; nil for an empty one.
  public init?(certificate: Data) {
    guard !certificate.isEmpty else { return nil }
    digest = Data(SHA256.hash(data: certificate))
  }

  /// A received fingerprint: 32 bytes, not all zero, since 32 zero bytes
  /// stand for an absent card.
  internal init?(received: Data) {
    guard received.count == Self.byteCount, received.contains(where: { $0 != 0 }) else {
      return nil
    }
    digest = received
  }
}
