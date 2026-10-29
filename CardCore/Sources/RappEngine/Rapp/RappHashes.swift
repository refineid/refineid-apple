// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// Transcript-bound digests the protocol derives from wire values.
internal enum RappHashes {
  /// The grant set as a digest: sorted and deduplicated first, so the same
  /// grants hash the same however the peer ordered them (RAPP v26.10.29
  /// §4.3 item 3).
  internal static func grantsHash(profiles: [String]) throws -> Data {
    let names = Array(Set(profiles)).sorted { left, right in
      Array(left.utf8).lexicographicallyPrecedes(Array(right.utf8))
    }
    let encoded = try WireValue.array(names.map { .text($0) }).encoded()
    return Data(SHA256.hash(data: encoded))
  }

  /// A profile may be exercised only if the pairing granted it.
  internal static func isGranted(profile: String, granted: [String]) -> Bool {
    granted.contains(profile)
  }
}
