// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// The nonces of the most recently routed sessions; a repeated one is a
/// replay.
internal struct RoutingReplayCache {
  internal static let window = 256

  private var seen: [Data] = []

  internal mutating func admit(_ nonce: Data) -> Bool {
    guard !seen.contains(nonce) else { return false }
    if seen.count == Self.window {
      seen.removeFirst()
    }
    seen.append(nonce)
    return true
  }
}
