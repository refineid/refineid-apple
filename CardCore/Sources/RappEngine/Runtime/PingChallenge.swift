// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The unpredictable value a ping carries and its pong must echo exactly.
///
/// The value is never described in a log or an error, so a debug description
/// would only leak it.
internal struct PingChallenge: Equatable, CustomStringConvertible {
  /// Bytes in the challenge a ping carries and a pong echoes.
  internal static let byteCount = 32

  private let value: Data

  internal var bytes: Data { value }

  internal var description: String { "PingChallenge([redacted])" }

  /// Builds a challenge from platform random bytes.
  internal init?(_ bytes: Data) {
    guard bytes.count == Self.byteCount else { return nil }
    value = bytes
  }

  /// The challenge a received `liveness.ping` carries or a `liveness.pong`
  /// echoes, the body's only field (RAPP v26.10.21 §7.1, §8.3); nil for any
  /// other body.
  internal init?(body: [String: WireValue]) {
    var fields = body
    guard let challenge = try? takeBytes(&fields, "challenge"), fields.isEmpty else {
      return nil
    }
    self.init(challenge)
  }
}
