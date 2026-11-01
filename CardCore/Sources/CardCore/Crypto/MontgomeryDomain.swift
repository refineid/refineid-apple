// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Montgomery arithmetic modulo one odd prime below `2^384`.
///
/// Residues are held as `value * R mod p` with `R = 2^384`, which keeps
/// multiplication, squaring and the lift in and out of the domain
/// division-free. Every constant is derived from the prime when the
/// domain is built, so the prime is the single transcribed value and
/// everything else follows from it. The same code serves every curve
/// PACE runs over: a prime narrower than 384 bits only leaves the top
/// limbs zero.
///
/// This type is deliberately not constant-time: it serves the
/// ephemeral, single-use PACE key agreement, matching the posture of
/// the Rust reference implementation.
///
/// Provenance: the arithmetic of the RefineID iOS browser donor
/// `Sources/RefineIDBrowserKit/Crypto/FieldP384.swift`, taken out of its
/// one fixed prime.
public struct MontgomeryDomain: Sendable {
  /// A full 384-by-384-bit product plus one carry limb for reduction.
  ///
  /// The width is invariant: `fullMultiply` always fills `wideLimbCount`
  /// limbs and `reduce` reads the same width back.
  private typealias WideLimbs = [UInt64]

  /// A product of two 384-bit values is twice as wide as either operand.
  private static let productWidthMultiple = 2

  /// Newton iterations needed to invert one 64-bit limb modulo 2^64.
  ///
  /// The iteration doubles the number of correct bits each round, so six
  /// rounds cover 64 bits from a one-bit start.
  private static let newtonIterations = 6

  /// The literal two used by Newton's iteration `x <- x * (2 - p0 * x)`.
  private static let newtonTwo: UInt64 = 2

  /// The number of limbs in a full 384-by-384-bit schoolbook product.
  private static let productLimbCount = U384.limbCount * productWidthMultiple

  /// The schoolbook product plus the one carry limb reduction pushes past
  /// it, which is the width `WideLimbs` always holds.
  private static let wideLimbCount = productLimbCount + 1

  /// Offsets into the high half of a wide product.
  private static let highLimbTwoOffset = 2
  private static let highLimbThreeOffset = 3
  private static let highLimbFourOffset = 4
  private static let highLimbFiveOffset = 5

  /// The modulus `p`.
  internal let prime: U384

  /// `2^384 - p`, the amount to add back when a sum overflows the
  /// 384-bit window: adding it is subtracting `p` modulo `2^384`.
  private let rMinusPrime: U384

  /// `-p^-1 mod 2^64`, the per-limb Montgomery reduction multiplier.
  private let inverseLowLimb: UInt64

  /// `R mod p`, one in the Montgomery domain.
  internal let one: U384

  /// `R^2 mod p`, the constant that lifts a residue into the domain.
  private let rSquared: U384

  /// The domain for the odd prime `prime`.
  internal init(prime: U384) {
    self.prime = prime
    self.rMinusPrime = U384.subtractingReportingBorrow(U384.zero, prime).difference
    let lowLimb = prime.limbs[0]
    var inverse: UInt64 = 1
    for _ in 0..<Self.newtonIterations {
      inverse = inverse &* (Self.newtonTwo &- lowLimb &* inverse)
    }
    self.inverseLowLimb = 0 &- inverse
    var accumulator = U384.one
    for _ in 0..<U384.bitCount {
      accumulator = Self.doubled(accumulator, prime: prime, rMinusPrime: rMinusPrime)
    }
    self.one = accumulator
    for _ in 0..<U384.bitCount {
      accumulator = Self.doubled(accumulator, prime: prime, rMinusPrime: rMinusPrime)
    }
    self.rSquared = accumulator
  }

  /// Doubles a residue already in `[0, p)`, staying in `[0, p)`.
  private static func doubled(_ value: U384, prime: U384, rMinusPrime: U384) -> U384 {
    let (shifted, carry) = value.shiftedLeftOne()
    guard carry == 0 else {
      return U384.addingReportingCarry(shifted, rMinusPrime).sum
    }
    return shifted >= prime ? U384.subtractingReportingBorrow(shifted, prime).difference : shifted
  }

  /// The full 384-by-384-bit schoolbook product as little-endian limbs.
  private static func fullMultiply(_ lhs: U384, _ rhs: U384) -> WideLimbs {
    var product = WideLimbs(repeating: 0, count: wideLimbCount)
    for outer in 0..<U384.limbCount {
      var carry: UInt64 = 0
      for inner in 0..<U384.limbCount {
        let (high, low) = lhs.limbs[inner].multipliedFullWidth(by: rhs.limbs[outer])
        let (partial, firstOverflow) = low.addingReportingOverflow(product[outer + inner])
        let (total, secondOverflow) = partial.addingReportingOverflow(carry)
        product[outer + inner] = total
        carry = high &+ (firstOverflow ? 1 : 0) &+ (secondOverflow ? 1 : 0)
      }
      product[outer + U384.limbCount] = carry
    }
    return product
  }

  /// Subtracts `p` once when the value is at least `p`.
  private func reducedOnce(_ value: U384) -> U384 {
    value >= prime ? U384.subtractingReportingBorrow(value, prime).difference : value
  }

  /// Montgomery reduction, separated-operand form: maps a wide product `T`
  /// below `p * R` to `T * R^-1 mod p`.
  ///
  /// The quotient before the final subtraction is below `2p`, which for a
  /// prime near `2^384` can reach past the 384-bit window; the carry limb
  /// above it decides the subtraction then.
  private func reduce(_ product: WideLimbs) -> U384 {
    var working = product
    for outer in 0..<U384.limbCount {
      let multiplier = working[outer] &* inverseLowLimb
      var carry: UInt64 = 0
      for inner in 0..<U384.limbCount {
        let (high, low) = multiplier.multipliedFullWidth(by: prime.limbs[inner])
        let (partial, firstOverflow) = low.addingReportingOverflow(working[outer + inner])
        let (total, secondOverflow) = partial.addingReportingOverflow(carry)
        working[outer + inner] = total
        carry = high &+ (firstOverflow ? 1 : 0) &+ (secondOverflow ? 1 : 0)
      }
      var index = outer + U384.limbCount
      while carry != 0, index < Self.wideLimbCount {
        let (sum, overflow) = working[index].addingReportingOverflow(carry)
        working[index] = sum
        carry = overflow ? 1 : 0
        index += 1
      }
    }
    let high = U384(
      limb0: working[U384.limbCount],
      limb1: working[U384.limbCount + 1],
      limb2: working[U384.limbCount + Self.highLimbTwoOffset],
      limb3: working[U384.limbCount + Self.highLimbThreeOffset],
      limb4: working[U384.limbCount + Self.highLimbFourOffset],
      limb5: working[U384.limbCount + Self.highLimbFiveOffset]
    )
    guard working[Self.productLimbCount] == 0 else {
      return U384.subtractingReportingBorrow(high, prime).difference
    }
    return reducedOnce(high)
  }

  /// The Montgomery product `lhs * rhs * R^-1 mod p`.
  internal func multiply(_ lhs: U384, _ rhs: U384) -> U384 {
    reduce(Self.fullMultiply(lhs, rhs))
  }

  /// Lifts any 384-bit value into the domain, reducing it modulo `p`.
  ///
  /// The value is below `R` and `R^2 mod p` below `p`, so their product
  /// is below `p * R`, which is all the reduction asks.
  internal func lifted(_ value: U384) -> U384 {
    multiply(value, rSquared)
  }

  /// The canonical residue in `[0, p)` of a Montgomery representation.
  internal func canonical(_ montgomery: U384) -> U384 {
    reduce(Self.fullMultiply(montgomery, U384.one))
  }

  /// `(lhs + rhs) mod p` on residues in `[0, p)`.
  internal func add(_ lhs: U384, _ rhs: U384) -> U384 {
    let (sum, carry) = U384.addingReportingCarry(lhs, rhs)
    guard carry == 0 else {
      return U384.addingReportingCarry(sum, rMinusPrime).sum
    }
    return reducedOnce(sum)
  }

  /// `(lhs - rhs) mod p` on residues in `[0, p)`.
  internal func subtract(_ lhs: U384, _ rhs: U384) -> U384 {
    let (difference, borrow) = U384.subtractingReportingBorrow(lhs, rhs)
    guard borrow == 0 else {
      return U384.addingReportingCarry(difference, prime).sum
    }
    return difference
  }

  /// `-value mod p` on a residue in `[0, p)`.
  internal func negate(_ value: U384) -> U384 {
    guard !value.isZero else { return value }
    return U384.subtractingReportingBorrow(prime, value).difference
  }

  /// `x * 2^-1 mod p`: halve an even value, or halve `x + p` when odd.
  private func halved(_ value: U384) -> U384 {
    guard value.limbs[0] & 1 == 1 else {
      return value.shiftedRightOne(carryIn: 0)
    }
    let (sum, carry) = U384.addingReportingCarry(value, prime)
    return sum.shiftedRightOne(carryIn: carry)
  }

  /// `a^-1 mod p` on canonical residues by the binary extended Euclidean
  /// algorithm, or nil when `a` is zero.
  ///
  /// About two hundred times faster than a Fermat exponentiation and fast
  /// enough for on-device PACE.
  internal func inverse(ofCanonical value: U384) -> U384? {
    guard !value.isZero else { return nil }
    var left = value
    var right = prime
    var leftCofactor = U384.one
    var rightCofactor = U384.zero
    while left != U384.one, right != U384.one {
      while left.limbs[0] & 1 == 0 {
        left = left.shiftedRightOne(carryIn: 0)
        leftCofactor = halved(leftCofactor)
      }
      while right.limbs[0] & 1 == 0 {
        right = right.shiftedRightOne(carryIn: 0)
        rightCofactor = halved(rightCofactor)
      }
      if left >= right {
        left = U384.subtractingReportingBorrow(left, right).difference
        leftCofactor = subtract(leftCofactor, rightCofactor)
      } else {
        right = U384.subtractingReportingBorrow(right, left).difference
        rightCofactor = subtract(rightCofactor, leftCofactor)
      }
    }
    return left == U384.one ? leftCofactor : rightCofactor
  }
}
