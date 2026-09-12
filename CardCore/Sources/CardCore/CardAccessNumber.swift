// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The six-digit card access number printed on the card.
///
/// The CAN authorizes READING the card in a field: it is the shared secret
/// PACE turns into a contactless session, and that is the whole of its
/// authority. It is not a signing credential. PIN1 still gates every
/// signature, and no PACE session established with this value can stand in
/// for it -- the two are different types precisely so one can never be
/// passed where the other is meant.
///
/// The CAN is never logged, never printed, and never committed. The type is
/// deliberately not `Codable`, not `CustomStringConvertible`, and hands out
/// no digits at all: the only value it yields is the PACE password key
/// derived from it. Its digits live in a `ZeroizingDigitStore`, so they are
/// overwritten when the last owner releases them.
///
/// Unlike a PIN the CAN consumes no retry counter, so it is copyable and
/// re-presentable; that is the one respect in which it is looser than
/// `Pin1`, and the reason is stated here rather than left to be inferred.
///
/// Provenance: the CAN handling of the RefineID iOS browser donor
/// `Sources/RefineIDBrowserKit/Card/Pace.swift`, whose `establish` took the
/// six digits as a bare `String` and validated them inline.
public struct CardAccessNumber: Sendable {
  /// The exact number of digits a card access number carries.
  public static let digitCount: Int = 6

  /// ASCII "0", the lowest byte a digit may encode as.
  private static let asciiDigitMinimum: UInt8 = 48

  /// ASCII "9", the highest byte a digit may encode as.
  private static let asciiDigitMaximum: UInt8 = 57

  /// The owned, zeroizing digit storage.
  private let store: ZeroizingDigitStore

  /// Validates and takes ownership of the entered digits.
  ///
  /// Refuses anything that is not exactly six ASCII digits; there is no
  /// other way to construct a `CardAccessNumber`, so every downstream use
  /// has compile-time evidence that validation happened.
  public init?(digits: String) {
    let bytes = Array(digits.utf8)
    guard
      bytes.count == Self.digitCount,
      bytes.allSatisfy({ byte in
        byte >= Self.asciiDigitMinimum && byte <= Self.asciiDigitMaximum
      })
    else {
      return nil
    }
    self.store = ZeroizingDigitStore(bytes: bytes)
  }

  /// The PACE password key derived from these digits.
  ///
  /// ICAO Doc 9303 part 11 section 9.7.2 encodes the CAN password as its
  /// ASCII digits with no further transformation, so the derivation input
  /// is exactly the stored bytes. This is the only thing the type exposes:
  /// callers get a derived key, never the digits, so no caller is in a
  /// position to log or transmit the CAN itself.
  internal func derivedPasswordKey() -> Data {
    PaceKeyDerivation.derivedKey(from: Data(store.bytes), for: .password)
  }
}
