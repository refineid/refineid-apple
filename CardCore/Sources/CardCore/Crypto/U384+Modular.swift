// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension U384 {
  /// The bits of one octet, most significant first.
  private static let octetBitIndices = stride(from: Self.bitsPerByte - 1, through: 0, by: -1)

  /// The big-endian integer `bytes` encodes, of any length, reduced modulo
  /// `modulus`.
  ///
  /// Horner's rule one bit at a time: the running residue is below the
  /// modulus, so doubling it and adding the next bit stays below twice the
  /// modulus, and one conditional subtraction brings it back -- including
  /// when the doubling pushed a bit out of the 384-bit window.
  internal static func reduced(bigEndian bytes: Data, modulo modulus: U384) -> U384 {
    var residue = Self.zero
    for byte in bytes {
      for index in octetBitIndices {
        let (shifted, carry) = residue.shiftedLeftOne()
        let next =
          (byte >> index) & 1 == 1
          ? Self.addingReportingCarry(shifted, .one).sum
          : shifted
        residue =
          carry != 0 || next >= modulus
          ? Self.subtractingReportingBorrow(next, modulus).difference
          : next
      }
    }
    return residue
  }
}
