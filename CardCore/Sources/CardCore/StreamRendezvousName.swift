// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security

/// The published names and attributes one side listens under and the
/// other browses for.
///
/// A pairing is found by attribute under a fresh random name (RAPP
/// discovery hierarchy §4.2 and §4.3): the offer is derived from the
/// pairing code, so any name derived from it would let a listener on the
/// network search the code space offline. Stored pairings still meet
/// under a name derived from their rendezvous token.
public enum StreamRendezvousName {
  // MARK: Static Properties

  /// How much of the digest the name carries.
  ///
  /// Enough that two ceremonies on one network do not collide; short
  /// enough to stay well inside a service name's length limit.
  private static let digestPrefixByteCount = 8

  /// Random bytes in an ephemeral instance name: eight hex characters.
  private static let ephemeralByteCount = 4

  private static let prefix = "rf-"
  private static let ephemeralPrefix = "refineid-"

  /// The attributes a custodian in pairing mode publishes.
  public static let pairingAttributes = ["v": "1", "mode": "pairing"]

  // MARK: Static Functions

  /// A fresh random instance name, drawn whenever advertising starts.
  public static func ephemeralName() -> String {
    var bytes = [UInt8](repeating: 0, count: ephemeralByteCount)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    precondition(status == errSecSuccess, "The system random source failed")
    return ephemeralPrefix + bytes.map { String(format: "%02x", $0) }.joined()
  }

  /// The name derived from a value both sides hold.
  ///
  /// A digest, never the value: a rendezvous token is bearer material, and
  /// a published name is broadcast to the network.
  public static func name(sharing value: Data) -> String {
    let digest = SHA256.hash(data: value)
    let hex = digest.prefix(digestPrefixByteCount)
      .map { String(format: "%02x", $0) }
      .joined()
    return prefix + hex
  }
}
