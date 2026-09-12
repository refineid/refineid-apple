// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// An element of GF(p) for the brainpoolP384r1 prime, held in Montgomery
/// form.
///
/// CryptoKit ships no Brainpool curve, so PACE on the FINEID card needs this
/// arithmetic in Swift. Values are stored as `value * R mod p` with
/// `R = 2^384`, which keeps multiplication, squaring and the lift in and out
/// of the domain division-free. The Montgomery constants are derived at load
/// time from `BrainpoolP384r1Values.prime`, so the prime is the single
/// transcribed value and everything else follows from it.
///
/// This type is deliberately not constant-time: it is used for the ephemeral,
/// single-use PACE key agreement, matching the posture of the Rust reference
/// implementation.
///
/// Provenance: lifted from the RefineID iOS browser donor
/// `Sources/RefineIDBrowserKit/Crypto/FieldP384.swift`.
internal struct FieldP384: Equatable, Sendable {
  /// A full 384-by-384-bit product plus one carry limb for reduction.
  ///
  /// The width is invariant: `fullMultiply` always fills `wideLimbCount`
  /// limbs and `montgomeryReduce` reads the same width back.
  private typealias WideLimbs = [UInt64]

  /// The field modulus `p`.
  internal static let prime = BrainpoolP384r1Values.prime

  /// Zero.
  internal static let zero = Self(montgomery: U384.zero)

  /// One, which in Montgomery form is `R mod p`.
  internal static let one = Self(montgomery: montgomeryOne)

  /// Three, the coefficient the tangent slope of a curve doubling needs.
  internal static let three = Self(U384(threeValue))

  /// The scalar three, named so the field constant carries no bare literal.
  private static let threeValue: UInt64 = 3

  /// A product of two 384-bit values is twice as wide as either operand.
  private static let productWidthMultiple = 2

  /// `2^384 - p`, the amount to add back when a doubling overflows the
  /// 384-bit window.
  ///
  /// Computed as `0 - p` modulo 2^384, which is exactly that difference.
  private static let rMinusPrime = U384.subtractingReportingBorrow(U384.zero, prime).difference

  /// Newton iterations needed to invert one 64-bit limb modulo 2^64.
  ///
  /// The iteration doubles the number of correct bits each round, so six
  /// rounds cover 64 bits from a one-bit start.
  private static let newtonIterations = 6

  /// The literal two used by Newton's iteration `x <- x * (2 - p0 * x)`.
  private static let newtonTwo: UInt64 = 2

  /// `-p^-1 mod 2^64`, the per-limb Montgomery reduction multiplier.
  private static let montgomeryInverseLowLimb: UInt64 = {
    let lowLimb = prime.limbs[0]
    var inverse: UInt64 = 1
    for _ in 0..<newtonIterations {
      inverse = inverse &* (newtonTwo &- lowLimb &* inverse)
    }
    return 0 &- inverse
  }()

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

  /// `R mod p`, obtained by doubling one 384 times: no division needed.
  private static let montgomeryOne: U384 = {
    var accumulator = U384.one
    for _ in 0..<U384.bitCount {
      accumulator = doubledModPrime(accumulator)
    }
    return accumulator
  }()

  /// `R^2 mod p`, the constant that lifts a canonical residue into the
  /// Montgomery domain; obtained by doubling one 768 times.
  private static let rSquared: U384 = {
    var accumulator = U384.one
    for _ in 0..<(U384.bitCount * productWidthMultiple) {
      accumulator = doubledModPrime(accumulator)
    }
    return accumulator
  }()

  /// The residue in Montgomery form.
  private let montgomery: U384

  /// True when this is the zero element.
  internal var isZero: Bool {
    montgomery.isZero
  }

  /// Lifts a residue into the field, reducing it modulo `p` if needed.
  ///
  /// Any 384-bit value is accepted: `p` is above `2^383`, so one conditional
  /// subtraction is enough to bring a value below `2^384` into `[0, p)`.
  internal init(_ value: U384) {
    montgomery = Self.montgomeryMultiply(Self.reducedOnce(value), Self.rSquared)
  }

  /// The element whose Montgomery representation is `montgomery`.
  private init(montgomery: U384) {
    self.montgomery = montgomery
  }

  /// Subtracts `p` once when the value is at least `p`.
  private static func reducedOnce(_ value: U384) -> U384 {
    value >= prime ? U384.subtractingReportingBorrow(value, prime).difference : value
  }

  /// Doubles a residue already in `[0, p)`, staying in `[0, p)`.
  private static func doubledModPrime(_ value: U384) -> U384 {
    let (shifted, carry) = value.shiftedLeftOne()
    guard carry == 0 else {
      return U384.addingReportingCarry(shifted, rMinusPrime).sum
    }
    return reducedOnce(shifted)
  }

  /// The full 384-by-384-bit schoolbook product as `productLimbCount`
  /// little-endian limbs.
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

  /// Montgomery reduction, separated-operand form: maps a wide product `T`
  /// below `p * R` to `T * R^-1 mod p`.
  private static func montgomeryReduce(_ product: WideLimbs) -> U384 {
    var working = product
    for outer in 0..<U384.limbCount {
      let multiplier = working[outer] &* montgomeryInverseLowLimb
      var carry: UInt64 = 0
      for inner in 0..<U384.limbCount {
        let (high, low) = multiplier.multipliedFullWidth(by: prime.limbs[inner])
        let (partial, firstOverflow) = low.addingReportingOverflow(working[outer + inner])
        let (total, secondOverflow) = partial.addingReportingOverflow(carry)
        working[outer + inner] = total
        carry = high &+ (firstOverflow ? 1 : 0) &+ (secondOverflow ? 1 : 0)
      }
      var index = outer + U384.limbCount
      while carry != 0 {
        let (sum, overflow) = working[index].addingReportingOverflow(carry)
        working[index] = sum
        carry = overflow ? 1 : 0
        index += 1
      }
    }
    let high = U384(
      limb0: working[U384.limbCount],
      limb1: working[U384.limbCount + 1],
      limb2: working[U384.limbCount + highLimbTwoOffset],
      limb3: working[U384.limbCount + highLimbThreeOffset],
      limb4: working[U384.limbCount + highLimbFourOffset],
      limb5: working[U384.limbCount + highLimbFiveOffset]
    )
    return reducedOnce(high)
  }

  /// The Montgomery product `lhs * rhs * R^-1 mod p`.
  private static func montgomeryMultiply(_ lhs: U384, _ rhs: U384) -> U384 {
    montgomeryReduce(fullMultiply(lhs, rhs))
  }

  /// `a^-1 mod p` on canonical residues by the binary extended Euclidean
  /// algorithm, or nil when `a` is zero.
  ///
  /// About two hundred times faster than a Fermat exponentiation and fast
  /// enough for on-device PACE.
  private static func binaryInverse(_ value: U384) -> U384? {
    guard !value.isZero else { return nil }
    var left = value
    var right = prime
    var leftCofactor = U384.one
    var rightCofactor = U384.zero
    while left != U384.one, right != U384.one {
      while left.limbs[0] & 1 == 0 {
        left = left.shiftedRightOne(carryIn: 0)
        leftCofactor = halvedModPrime(leftCofactor)
      }
      while right.limbs[0] & 1 == 0 {
        right = right.shiftedRightOne(carryIn: 0)
        rightCofactor = halvedModPrime(rightCofactor)
      }
      if left >= right {
        left = U384.subtractingReportingBorrow(left, right).difference
        leftCofactor = subtractedModPrime(leftCofactor, rightCofactor)
      } else {
        right = U384.subtractingReportingBorrow(right, left).difference
        rightCofactor = subtractedModPrime(rightCofactor, leftCofactor)
      }
    }
    return left == U384.one ? leftCofactor : rightCofactor
  }

  /// `x * 2^-1 mod p`: halve an even value, or halve `x + p` when odd.
  private static func halvedModPrime(_ value: U384) -> U384 {
    guard value.limbs[0] & 1 == 1 else {
      return value.shiftedRightOne(carryIn: 0)
    }
    let (sum, carry) = U384.addingReportingCarry(value, prime)
    return sum.shiftedRightOne(carryIn: carry)
  }

  /// `(lhs - rhs) mod p` on canonical residues in `[0, p)`.
  private static func subtractedModPrime(_ lhs: U384, _ rhs: U384) -> U384 {
    guard lhs < rhs else {
      return U384.subtractingReportingBorrow(lhs, rhs).difference
    }
    let wrapped = U384.subtractingReportingBorrow(lhs, rhs).difference
    return U384.addingReportingCarry(wrapped, prime).sum
  }

  /// The canonical residue in `[0, p)`.
  internal func value() -> U384 {
    Self.montgomeryReduce(Self.fullMultiply(montgomery, U384.one))
  }

  /// The sum of this element and `other`.
  internal func adding(_ other: Self) -> Self {
    let (sum, carry) = U384.addingReportingCarry(montgomery, other.montgomery)
    guard carry == 0 else {
      return Self(montgomery: U384.addingReportingCarry(sum, Self.rMinusPrime).sum)
    }
    return Self(montgomery: Self.reducedOnce(sum))
  }

  /// This element less `other`.
  internal func subtracting(_ other: Self) -> Self {
    let (difference, borrow) = U384.subtractingReportingBorrow(montgomery, other.montgomery)
    guard borrow == 0 else {
      return Self(montgomery: U384.addingReportingCarry(difference, Self.prime).sum)
    }
    return Self(montgomery: difference)
  }

  /// The additive inverse.
  internal func negated() -> Self {
    guard !isZero else { return self }
    return Self(
      montgomery: U384.subtractingReportingBorrow(Self.prime, montgomery).difference
    )
  }

  /// The product of this element and `other`.
  internal func multiplied(by other: Self) -> Self {
    Self(montgomery: Self.montgomeryMultiply(montgomery, other.montgomery))
  }

  /// This element squared.
  internal func squared() -> Self {
    Self(montgomery: Self.montgomeryMultiply(montgomery, montgomery))
  }

  /// The multiplicative inverse, or nil for zero.
  ///
  /// Zero has no inverse, so the caller has to say what a zero denominator
  /// means; on this curve it means the point at infinity.
  internal func inverted() -> Self? {
    guard let inverse = Self.binaryInverse(value()) else { return nil }
    return Self(inverse)
  }
}
