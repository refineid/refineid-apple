// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// Transcript-bound digests the protocol derives from wire values.
internal enum RappHashes {
  private static let requestDomain = "RAPP-request-v1"

  /// The grant set as a digest: sorted and deduplicated first, so the same
  /// grants hash the same however the peer ordered them.
  internal static func grantsHash(profiles: [String]) throws -> Data {
    let names = Array(Set(profiles)).sorted { left, right in
      Array(left.utf8).lexicographicallyPrecedes(Array(right.utf8))
    }
    let encoded = try WireValue.array(names.map { .text($0) }).encoded()
    return Data(SHA256.hash(data: encoded))
  }

  /// Binds one typed request to its session, so a committed request cannot be
  /// swapped for another.
  internal static func requestPreimage(of request: RappRequestBinding) throws -> Data {
    let value = WireValue.array([
      .text(requestDomain),
      .bytes(request.pairIdentifier),
      .bytes(request.operationIdentifier),
      .text(request.profile),
      .text(request.action),
      .map(request.context),
      .map(request.payload),
    ])
    return try value.encoded()
  }

  internal static func requestHash(of request: RappRequestBinding) throws -> Data {
    Data(SHA256.hash(data: try requestPreimage(of: request)))
  }

  /// A profile may be exercised only if the pairing granted it.
  internal static func isGranted(profile: String, granted: [String]) -> Bool {
    granted.contains(profile)
  }
}
