// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The secure-messaging session PACE yields: Kenc, Kmac and the initial
/// send-sequence counter.
///
/// The two keys are the AES-256 keys derived from the PACE shared secret --
/// one for the DO'87' cryptogram, one for the DO'8E' checksum -- and the
/// counter is the third member of the triple because a key pair without the
/// counter is not a usable channel: the SSC is what makes each message
/// unique and it must start where the card's does, at zero
/// (ICAO Doc 9303 part 11 section 9.8.7).
///
/// The keys are key material. They are held internally and never handed out:
/// the type is not `Codable` and not `CustomStringConvertible`, the only
/// module that reads the keys is `SecureMessagingChannel`, and equality is
/// constant time so that comparing two sessions cannot become a byte-by-byte
/// oracle.
///
/// Provenance: replaces `PaceSession` of the RefineID iOS browser donor
/// `Sources/RefineIDBrowserKit/Card/Pace.swift`, whose fields were mutable
/// `[UInt8]` with no length validation.
public struct PaceSessionKeys: Equatable, Sendable {
  /// The length in bytes of each derived key: an AES-256 key.
  public static let keyLength: Int = PaceKeyDerivation.derivedKeyLength

  /// The secure-messaging encryption key, Kenc.
  internal let encryptionKey: Data

  /// The secure-messaging authentication key, Kmac.
  internal let macKey: Data

  /// The send-sequence counter the channel starts from: one AES block of
  /// zeros, pre-incremented before the first command.
  internal let initialSendSequenceCounter: Data

  /// Takes a pair of derived keys, refusing anything that is not an
  /// AES-256 key length.
  ///
  /// The counter is not a parameter: it always starts at zero after a
  /// successful PACE run, so making it settable would only make a
  /// desynchronized channel representable.
  public init?(encryptionKey: Data, macKey: Data) {
    guard
      encryptionKey.count == Self.keyLength,
      macKey.count == Self.keyLength
    else {
      return nil
    }
    self.encryptionKey = encryptionKey
    self.macKey = macKey
    self.initialSendSequenceCounter = Data(
      repeating: 0,
      count: PaceValues.sendSequenceCounterLength
    )
  }

  /// Constant-time equality over both keys.
  ///
  /// Written by hand rather than synthesized: `Data`'s own `==` returns as
  /// soon as two bytes differ, and these operands are key material. Both
  /// comparisons are made before they are combined, so the second is not
  /// short-circuited away when the first already failed.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    let encryptionMatches = ConstantTimeComparison.equal(lhs.encryptionKey, rhs.encryptionKey)
    let macMatches = ConstantTimeComparison.equal(lhs.macKey, rhs.macKey)
    return encryptionMatches && macMatches
  }
}
