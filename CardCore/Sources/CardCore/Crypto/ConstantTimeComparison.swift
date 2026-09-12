// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Equality on bytes a card or a peer supplied, in time that depends only
/// on their length.
///
/// Every comparison in this module whose operands are key material, a
/// message authentication code, or an authentication token goes through
/// here. `Data`'s own `==` returns as soon as two bytes differ, which turns
/// a comparison against an attacker-supplied value into a byte-by-byte
/// oracle: the expected tag can be learned one byte at a time from how long
/// each rejection takes.
///
/// The length check is deliberately not constant time. Lengths are public in
/// every protocol here -- a truncated checksum data object is visible on the
/// wire -- so revealing that two buffers differ in length reveals nothing an
/// observer did not already have.
///
/// Provenance: the `constantTimeEqual` helpers of the RefineID iOS browser
/// donor `Sources/RefineIDBrowserKit/Card/Pace.swift` and
/// `Sources/RefineIDBrowserKit/Card/SecureMessaging.swift`, which carried
/// one private copy each.
internal enum ConstantTimeComparison {
  /// True when both buffers have the same length and the same contents.
  internal static func equal(_ lhs: Data, _ rhs: Data) -> Bool {
    guard lhs.count == rhs.count else { return false }
    var difference: UInt8 = 0
    for (left, right) in zip(lhs, rhs) {
      difference |= left ^ right
    }
    return difference == 0
  }
}
