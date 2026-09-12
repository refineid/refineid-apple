// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A 384-bit unsigned integer held as six little-endian 64-bit limbs.
///
/// Limb 0 is the least significant. This is the storage the brainpoolP384r1
/// field and curve arithmetic are written against; it carries no modulus of
/// its own, so `addingReportingCarry` and `subtractingReportingBorrow`
/// report the bit that leaves the 384-bit window instead of hiding it.
///
/// Provenance: lifted from the RefineID iOS browser donor
/// `Sources/RefineIDBrowserKit/Crypto/FieldP384.swift`. The donor's
/// hex-string initializer force-unwrapped `UInt8(_:radix:)` and its limb
/// initializer used `precondition`; both are replaced here by a total
/// six-limb initializer (curve constants live in `BrainpoolP384r1Values`)
/// and a failable big-endian byte initializer.
public struct U384: Equatable, Comparable, Sendable {
  /// The limb storage, always exactly `limbCount` elements.
  ///
  /// Every initializer here produces that width and no operation changes it,
  /// so the count is an invariant of the type rather than something callers
  /// pass around.
  internal typealias Limbs = [UInt64]

  /// Storage with every limb clear, the starting point of each operation.
  internal static var zeroLimbs: Limbs { Limbs(repeating: 0, count: limbCount) }

  /// The number of 64-bit limbs in the representation.
  public static let limbCount = 6

  /// The width of one limb in bits.
  internal static let limbBits = 64

  /// The width of one byte in bits.
  internal static let bitsPerByte = 8

  /// The number of bytes in one limb.
  internal static let bytesPerLimb = 8

  /// The fixed width of the big-endian encoding, 48 bytes for 384 bits.
  public static let byteCount = limbCount * bytesPerLimb

  /// The total width in bits.
  public static let bitCount = limbCount * limbBits

  /// The additive identity.
  public static let zero = Self()

  /// The multiplicative identity.
  public static let one = Self(1)

  /// The six limbs, least significant first.
  internal let limbs: Limbs

  /// True when every limb is zero.
  public var isZero: Bool {
    for index in 0..<Self.limbCount where limbs[index] != 0 {
      return false
    }
    return true
  }

  /// The index of the most significant set bit, or nil when the value is
  /// zero.
  ///
  /// Scalar multiplication starts at this bit so a small scalar costs a
  /// small number of doublings.
  internal var highestSetBitIndex: Int? {
    for limb in stride(from: Self.limbCount - 1, through: 0, by: -1)
    where limbs[limb] != 0 {
      return limb * Self.limbBits + (Self.limbBits - 1 - limbs[limb].leadingZeroBitCount)
    }
    return nil
  }

  /// Zero.
  public init() {
    limbs = Self.zeroLimbs
  }

  /// A small value that fits in the least significant limb.
  public init(_ value: UInt64) {
    limbs = [value, 0, 0, 0, 0, 0]
  }

  /// The value with the six given little-endian limbs.
  ///
  /// Total by construction: the compiler enforces exactly six limbs, so
  /// there is no count to validate and no parse to unwrap. This is how the
  /// curve constants in `BrainpoolP384r1Values` are written.
  internal init(
    limb0: UInt64,
    limb1: UInt64,
    limb2: UInt64,
    limb3: UInt64,
    limb4: UInt64,
    limb5: UInt64
  ) {
    limbs = [limb0, limb1, limb2, limb3, limb4, limb5]
  }

  /// The value whose storage is already exactly six limbs.
  private init(limbs: Limbs) {
    self.limbs = limbs
  }

  /// The value encoded by up to `byteCount` big-endian bytes, or nil when
  /// the input is wider than 384 bits.
  ///
  /// Short inputs are left-padded with zeros, matching how card and TLS
  /// wire formats carry fixed-width field elements.
  public init?(bigEndianBytes: Data) {
    guard bigEndianBytes.count <= Self.byteCount else { return nil }
    var padded = [UInt8](repeating: 0, count: Self.byteCount)
    padded.replaceSubrange(
      (Self.byteCount - bigEndianBytes.count)..<Self.byteCount,
      with: bigEndianBytes
    )
    var built = Self.zeroLimbs
    for limb in 0..<Self.limbCount {
      let base = (Self.limbCount - 1 - limb) * Self.bytesPerLimb
      var value: UInt64 = 0
      for offset in 0..<Self.bytesPerLimb {
        value = (value << Self.bitsPerByte) | UInt64(padded[base + offset])
      }
      built[limb] = value
    }
    limbs = built
  }

  /// Two values are equal when all six limbs match.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    for index in 0..<Self.limbCount where lhs.limbs[index] != rhs.limbs[index] {
      return false
    }
    return true
  }

  /// Orders two values by magnitude, most significant limb first.
  public static func < (lhs: Self, rhs: Self) -> Bool {
    for index in stride(from: Self.limbCount - 1, through: 0, by: -1)
    where lhs.limbs[index] != rhs.limbs[index] {
      return lhs.limbs[index] < rhs.limbs[index]
    }
    return false
  }

  /// The sum modulo 2^384 together with the carry that left the window.
  ///
  /// The caller decides what the carry means; this type knows no modulus.
  internal static func addingReportingCarry(
    _ lhs: Self,
    _ rhs: Self
  ) -> (sum: Self, carry: UInt64) {
    var out = Self.zeroLimbs
    var carry: UInt64 = 0
    for index in 0..<Self.limbCount {
      let (partial, firstOverflow) = lhs.limbs[index].addingReportingOverflow(rhs.limbs[index])
      let (total, secondOverflow) = partial.addingReportingOverflow(carry)
      out[index] = total
      carry = (firstOverflow ? 1 : 0) + (secondOverflow ? 1 : 0)
    }
    return (Self(limbs: out), carry)
  }

  /// The difference modulo 2^384 together with the borrow that left the
  /// window.
  internal static func subtractingReportingBorrow(
    _ lhs: Self,
    _ rhs: Self
  ) -> (difference: Self, borrow: UInt64) {
    var out = Self.zeroLimbs
    var borrow: UInt64 = 0
    for index in 0..<Self.limbCount {
      let (partial, firstBorrow) = lhs.limbs[index]
        .subtractingReportingOverflow(rhs.limbs[index])
      let (total, secondBorrow) = partial.subtractingReportingOverflow(borrow)
      out[index] = total
      borrow = (firstBorrow ? 1 : 0) + (secondBorrow ? 1 : 0)
    }
    return (Self(limbs: out), borrow)
  }

  /// The fixed-width 48-byte big-endian encoding.
  public func bigEndianBytes() -> Data {
    var out = [UInt8](repeating: 0, count: Self.byteCount)
    for limb in 0..<Self.limbCount {
      let value = limbs[limb]
      let base = (Self.limbCount - 1 - limb) * Self.bytesPerLimb
      for offset in 0..<Self.bytesPerLimb {
        let shift = Self.bitsPerByte * (Self.bytesPerLimb - 1 - offset)
        out[base + offset] = UInt8(truncatingIfNeeded: value >> shift)
      }
    }
    return Data(out)
  }

  /// True when the bit at `index` is set, counting from the least
  /// significant bit; out-of-range indices read as clear.
  internal func bit(at index: Int) -> Bool {
    guard index >= 0, index < Self.bitCount else { return false }
    return (limbs[index / Self.limbBits] >> (index % Self.limbBits)) & 1 == 1
  }

  /// The value doubled modulo 2^384, with the bit that left the window.
  internal func shiftedLeftOne() -> (value: Self, carry: UInt64) {
    var out = Self.zeroLimbs
    var carry: UInt64 = 0
    for index in 0..<Self.limbCount {
      out[index] = (limbs[index] << 1) | carry
      carry = limbs[index] >> (Self.limbBits - 1)
    }
    return (Self(limbs: out), carry)
  }

  /// The value halved, with `carryIn` shifted into the most significant
  /// bit.
  ///
  /// The caller supplies the carry that a preceding addition pushed out of
  /// the window, so a 385-bit intermediate can be halved without widening
  /// the type.
  internal func shiftedRightOne(carryIn: UInt64) -> Self {
    var out = Self.zeroLimbs
    var carry = carryIn & 1
    for index in stride(from: Self.limbCount - 1, through: 0, by: -1) {
      let next = limbs[index] & 1
      out[index] = (limbs[index] >> 1) | (carry << (Self.limbBits - 1))
      carry = next
    }
    return Self(limbs: out)
  }
}
