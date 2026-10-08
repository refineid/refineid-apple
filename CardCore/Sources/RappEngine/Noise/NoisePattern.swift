// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A Noise handshake pattern: what each side knows in advance and the
/// token sequence of each message.
internal struct NoisePattern {
  /// `XXpsk3`: mutual static exchange with the shared secret mixed last.
  internal static let xxPsk3 = Self(
    name: "XXpsk3",
    initiatorPreMessage: [],
    responderPreMessage: [],
    messages: [
      [.ephemeral],
      [.ephemeral, .ephemeralEphemeral, .staticKey, .ephemeralStatic],
      [.staticKey, .staticEphemeral, .presharedKey],
    ])

  /// `KK`: both statics are already known to the other side.
  internal static let knownKnown = Self(
    name: "KK",
    initiatorPreMessage: [.staticKey],
    responderPreMessage: [.staticKey],
    messages: [
      [.ephemeral, .ephemeralStatic, .staticStatic],
      [.ephemeral, .ephemeralEphemeral, .staticEphemeral],
    ])

  internal let name: String
  internal let initiatorPreMessage: [NoiseToken]
  internal let responderPreMessage: [NoiseToken]
  internal let messages: [[NoiseToken]]

  internal var usesPresharedKey: Bool {
    messages.contains { $0.contains(.presharedKey) }
  }
}
