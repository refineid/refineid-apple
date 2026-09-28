// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

// swiftlint:disable no_magic_numbers

extension FieldElement51 {
  private struct CrossProducts {
    var prod0: UInt128
    var prod1: UInt128
    var prod2: UInt128
    var prod3: UInt128
    var prod4: UInt128
  }

  @inline(__always)
  private static func mulLimb(_ xVal: UInt64, _ yVal: UInt64) -> UInt128 {
    UInt128(xVal) * UInt128(yVal)
  }

  private static func computeCrossProducts(
    lhs: Self,
    rhs: Self
  ) -> CrossProducts {
    let termA0 = lhs.limb0
    let termA1 = lhs.limb1
    let termA2 = lhs.limb2
    let termA3 = lhs.limb3
    let termA4 = lhs.limb4

    let termB0 = rhs.limb0
    let mul19B1 = rhs.limb1 * 19
    let mul19B2 = rhs.limb2 * 19
    let mul19B3 = rhs.limb3 * 19
    let mul19B4 = rhs.limb4 * 19

    let prod0 =
      mulLimb(termA0, termB0) + mulLimb(termA4, mul19B1) + mulLimb(termA3, mul19B2)
      + mulLimb(termA2, mul19B3) + mulLimb(termA1, mul19B4)
    let prod1 =
      mulLimb(termA1, termB0) + mulLimb(termA0, rhs.limb1) + mulLimb(termA4, mul19B2)
      + mulLimb(termA3, mul19B3) + mulLimb(termA2, mul19B4)
    let prod2 =
      mulLimb(termA2, termB0) + mulLimb(termA1, rhs.limb1) + mulLimb(termA0, rhs.limb2)
      + mulLimb(termA4, mul19B3) + mulLimb(termA3, mul19B4)
    let prod3 =
      mulLimb(termA3, termB0) + mulLimb(termA2, rhs.limb1) + mulLimb(termA1, rhs.limb2)
      + mulLimb(termA0, rhs.limb3) + mulLimb(termA4, mul19B4)
    let prod4 =
      mulLimb(termA4, termB0) + mulLimb(termA3, rhs.limb1) + mulLimb(termA2, rhs.limb2)
      + mulLimb(termA1, rhs.limb3) + mulLimb(termA0, rhs.limb4)

    return CrossProducts(
      prod0: prod0,
      prod1: prod1,
      prod2: prod2,
      prod3: prod3,
      prod4: prod4
    )
  }

  private static func carryReduce(_ prod: CrossProducts) -> Self {
    let mask = Self.mask51
    let prod0 = prod.prod0
    var prod1 = prod.prod1
    var prod2 = prod.prod2
    var prod3 = prod.prod3
    var prod4 = prod.prod4

    prod1 += prod0 >> 51
    var out0 = UInt64(truncatingIfNeeded: prod0) & mask

    prod2 += prod1 >> 51
    let out1 = UInt64(truncatingIfNeeded: prod1) & mask

    prod3 += prod2 >> 51
    let out2 = UInt64(truncatingIfNeeded: prod2) & mask

    prod4 += prod3 >> 51
    let out3 = UInt64(truncatingIfNeeded: prod3) & mask

    let carry = UInt64(truncatingIfNeeded: prod4 >> 51)
    let out4 = UInt64(truncatingIfNeeded: prod4) & mask

    out0 += carry * 19
    var res1 = out1 + (out0 >> 51)
    let res0 = out0 & mask
    let res2 = out2 + (res1 >> 51)
    res1 &= mask

    return Self(limb0: res0, limb1: res1, limb2: res2, limb3: out3, limb4: out4)
  }

  internal static func + (lhs: Self, rhs: Self) -> Self {
    Self(
      limb0: lhs.limb0 + rhs.limb0,
      limb1: lhs.limb1 + rhs.limb1,
      limb2: lhs.limb2 + rhs.limb2,
      limb3: lhs.limb3 + rhs.limb3,
      limb4: lhs.limb4 + rhs.limb4
    )
  }

  internal static func - (lhs: Self, rhs: Self) -> Self {
    Self(
      limb0: (lhs.limb0 + 36_028_797_018_963_664) - rhs.limb0,
      limb1: (lhs.limb1 + 36_028_797_018_963_952) - rhs.limb1,
      limb2: (lhs.limb2 + 36_028_797_018_963_952) - rhs.limb2,
      limb3: (lhs.limb3 + 36_028_797_018_963_952) - rhs.limb3,
      limb4: (lhs.limb4 + 36_028_797_018_963_952) - rhs.limb4
    ).reduced()
  }

  internal static prefix func - (operand: Self) -> Self {
    operand.negated()
  }

  internal static func * (lhs: Self, rhs: Self) -> Self {
    carryReduce(computeCrossProducts(lhs: lhs, rhs: rhs))
  }

  internal static func * (lhs: Self, rhs: Int) -> Self {
    if rhs == 2 {
      return lhs + lhs
    }
    return lhs * Self(limb0: UInt64(rhs), limb1: 0, limb2: 0, limb3: 0, limb4: 0)
  }

  /// RFC 9496 Section 4.2: Square root of a ratio of field elements.
  internal static func sqrtRatioI(
    elemU: Self,
    elemV: Self
  ) -> (wasSquare: Bool, rVal: Self) {
    let denV3 = elemV.square() * elemV
    let denV7 = denV3.square() * elemV
    var resR = (elemU * denV3) * (elemU * denV7).powP58()
    let check = elemV * resR.square()

    let sqrtM1Val = Self.sqrtM1
    let correctSign = check == elemU
    let flippedSign = check == -elemU
    let flippedSignI = check == (-elemU) * sqrtM1Val

    let rPrime = sqrtM1Val * resR
    if flippedSign || flippedSignI {
      resR = rPrime
    }
    if resR.isNegative {
      resR = -resR
    }
    let wasSquare = correctSign || flippedSign
    return (wasSquare, resR)
  }

  internal func negated() -> Self {
    Self.zero - self
  }

  internal func doubled() -> Self {
    self + self
  }

  internal func square() -> Self {
    self * self
  }

  internal func square2() -> Self {
    let sqVal = square()
    return sqVal + sqVal
  }

  private func pow2k(_ count: Int) -> Self {
    var resVal = self
    for _ in 0..<count {
      resVal = resVal.square()
    }
    return resVal
  }

  private func pow22501() -> (Self, Self) {
    let step0 = square()
    let step1 = step0.square().square()
    let step2 = self * step1
    let step3 = step0 * step2
    let step4 = step3.square()
    let step5 = step2 * step4
    let step6 = step5.pow2k(5)
    let step7 = step6 * step5
    let step8 = step7.pow2k(10)
    let step9 = step8 * step7
    let step10 = step9.pow2k(20)
    let step11 = step10 * step9
    let step12 = step11.pow2k(10)
    let step13 = step12 * step7
    let step14 = step13.pow2k(50)
    let step15 = step14 * step13
    let step16 = step15.pow2k(100)
    let step17 = step16 * step15
    let step18 = step17.pow2k(50)
    let step19 = step18 * step13
    return (step19, step3)
  }

  internal func powP58() -> Self {
    let (step19, _) = pow22501()
    let step20 = step19.pow2k(2)
    return self * step20
  }

  internal func invert() -> Self {
    let (step19, step3) = pow22501()
    let step20 = step19.pow2k(5)
    return step20 * step3
  }
}

// swiftlint:enable no_magic_numbers
