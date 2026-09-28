// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

// swiftlint:disable no_magic_numbers

/// Field element in GF(2^255 - 19) represented as 5 51-bit limbs in UInt64.
internal struct FieldElement51: Equatable, Sendable {
  internal static let mask51: UInt64 = (1 << 51) - 1

  // RFC 9496 Section 4.1 Constants
  internal static let zero = Self()
  internal static let one = Self(limb0: 1, limb1: 0, limb2: 0, limb3: 0, limb4: 0)
  internal static let minusOne = Self(
    limb0: 2_251_799_813_685_228,
    limb1: 2_251_799_813_685_247,
    limb2: 2_251_799_813_685_247,
    limb3: 2_251_799_813_685_247,
    limb4: 2_251_799_813_685_247
  )

  // Edwards d parameter: -121665/121666 mod (2^255 - 19)
  internal static let edwardsD = Self(
    limb0: 929_955_233_495_203,
    limb1: 466_365_720_129_213,
    limb2: 1_662_059_464_998_953,
    limb3: 2_033_849_074_728_123,
    limb4: 1_442_794_654_840_575
  )

  // SQRT_M1 = 2^((p-1)/4) mod p
  internal static let sqrtM1 = Self(
    limb0: 1_718_705_420_411_056,
    limb1: 234_908_883_556_509,
    limb2: 2_233_514_472_574_048,
    limb3: 2_117_202_627_021_982,
    limb4: 765_476_049_583_133
  )

  // SQRT_AD_MINUS_ONE
  internal static let sqrtAdMinusOne = Self(
    limb0: 2_241_493_124_984_347,
    limb1: 425_987_919_032_274,
    limb2: 2_207_028_919_301_688,
    limb3: 1_220_490_630_685_848,
    limb4: 974_799_131_293_748
  )

  // INVSQRT_A_MINUS_D
  internal static let invsqrtAMinusD = Self(
    limb0: 278_908_739_862_762,
    limb1: 821_645_201_101_625,
    limb2: 8_113_234_426_968,
    limb3: 1_777_959_178_193_151,
    limb4: 2_118_520_810_568_447
  )

  // ONE_MINUS_D_SQ
  internal static let oneMinusDSq = Self(
    limb0: 1_136_626_929_484_150,
    limb1: 1_998_550_399_581_263,
    limb2: 496_427_632_559_748,
    limb3: 118_527_312_129_759,
    limb4: 45_110_755_273_534
  )

  // D_MINUS_ONE_SQ
  internal static let dMinusOneSq = Self(
    limb0: 1_507_062_230_895_904,
    limb1: 1_572_317_787_530_805,
    limb2: 683_053_064_812_840,
    limb3: 317_374_165_784_489,
    limb4: 1_572_899_562_415_810
  )

  internal var limb0: UInt64
  internal var limb1: UInt64
  internal var limb2: UInt64
  internal var limb3: UInt64
  internal var limb4: UInt64

  internal var isNegative: Bool {
    let bytes = canonicalBytes()
    return (bytes[0] & 1) == 1
  }

  internal var isZero: Bool {
    let bytes = canonicalBytes()
    return bytes.allSatisfy { $0 == 0 }
  }

  internal init() {
    self.limb0 = 0
    self.limb1 = 0
    self.limb2 = 0
    self.limb3 = 0
    self.limb4 = 0
  }

  internal init(
    limb0: UInt64,
    limb1: UInt64,
    limb2: UInt64,
    limb3: UInt64,
    limb4: UInt64
  ) {
    self.limb0 = limb0
    self.limb1 = limb1
    self.limb2 = limb2
    self.limb3 = limb3
    self.limb4 = limb4
  }

  internal init(bytes: Data) {
    let arr = [UInt8](bytes)
    let mask = Self.mask51
    func load8(_ offset: Int) -> UInt64 {
      var result: UInt64 = 0
      for idx in 0..<8 {
        let pos = offset + idx
        if pos < arr.count {
          result |= UInt64(arr[pos]) << (idx * 8)
        }
      }
      return result
    }

    self.limb0 = load8(0) & mask
    self.limb1 = (load8(6) >> 3) & mask
    self.limb2 = (load8(12) >> 6) & mask
    self.limb3 = (load8(19) >> 1) & mask
    self.limb4 = (load8(24) >> 12) & mask
  }

  private static func packBytes(
    limb0: UInt64,
    limb1: UInt64,
    limb2: UInt64,
    limb3: UInt64,
    limb4: UInt64
  ) -> Data {
    var bytes = [UInt8](repeating: 0, count: 32)
    bytes[0] = UInt8(truncatingIfNeeded: limb0)
    bytes[1] = UInt8(truncatingIfNeeded: limb0 >> 8)
    bytes[2] = UInt8(truncatingIfNeeded: limb0 >> 16)
    bytes[3] = UInt8(truncatingIfNeeded: limb0 >> 24)
    bytes[4] = UInt8(truncatingIfNeeded: limb0 >> 32)
    bytes[5] = UInt8(truncatingIfNeeded: limb0 >> 40)
    bytes[6] = UInt8(truncatingIfNeeded: (limb0 >> 48) | (limb1 << 3))
    bytes[7] = UInt8(truncatingIfNeeded: limb1 >> 5)
    bytes[8] = UInt8(truncatingIfNeeded: limb1 >> 13)
    bytes[9] = UInt8(truncatingIfNeeded: limb1 >> 21)
    bytes[10] = UInt8(truncatingIfNeeded: limb1 >> 29)
    bytes[11] = UInt8(truncatingIfNeeded: limb1 >> 37)
    bytes[12] = UInt8(truncatingIfNeeded: (limb1 >> 45) | (limb2 << 6))
    bytes[13] = UInt8(truncatingIfNeeded: limb2 >> 2)
    bytes[14] = UInt8(truncatingIfNeeded: limb2 >> 10)
    bytes[15] = UInt8(truncatingIfNeeded: limb2 >> 18)
    bytes[16] = UInt8(truncatingIfNeeded: limb2 >> 26)
    bytes[17] = UInt8(truncatingIfNeeded: limb2 >> 34)
    bytes[18] = UInt8(truncatingIfNeeded: limb2 >> 42)
    bytes[19] = UInt8(truncatingIfNeeded: (limb2 >> 50) | (limb3 << 1))
    bytes[20] = UInt8(truncatingIfNeeded: limb3 >> 7)
    bytes[21] = UInt8(truncatingIfNeeded: limb3 >> 15)
    bytes[22] = UInt8(truncatingIfNeeded: limb3 >> 23)
    bytes[23] = UInt8(truncatingIfNeeded: limb3 >> 31)
    bytes[24] = UInt8(truncatingIfNeeded: limb3 >> 39)
    bytes[25] = UInt8(truncatingIfNeeded: (limb3 >> 47) | (limb4 << 4))
    bytes[26] = UInt8(truncatingIfNeeded: limb4 >> 4)
    bytes[27] = UInt8(truncatingIfNeeded: limb4 >> 12)
    bytes[28] = UInt8(truncatingIfNeeded: limb4 >> 20)
    bytes[29] = UInt8(truncatingIfNeeded: limb4 >> 28)
    bytes[30] = UInt8(truncatingIfNeeded: limb4 >> 36)
    bytes[31] = UInt8(truncatingIfNeeded: limb4 >> 44)
    return Data(bytes)
  }

  internal static func fromHex(_ hexString: String) -> Self {
    var rawBytes = [UInt8]()
    var strIndex = hexString.startIndex
    while strIndex < hexString.endIndex {
      let nextIndex = hexString.index(strIndex, offsetBy: 2)
      if let byteVal = UInt8(hexString[strIndex..<nextIndex], radix: 16) {
        rawBytes.append(byteVal)
      }
      strIndex = nextIndex
    }
    return Self(bytes: Data(rawBytes))
  }

  internal static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.canonicalBytes() == rhs.canonicalBytes()
  }

  /// Weak reduction to keep limbs within 51 bits.
  internal func reduced() -> Self {
    let mask = Self.mask51
    let carry0 = limb0 >> 51
    let carry1 = limb1 >> 51
    let carry2 = limb2 >> 51
    let carry3 = limb3 >> 51
    let carry4 = limb4 >> 51

    var out0 = (limb0 & mask) + carry4 * 19
    var out1 = (limb1 & mask) + carry0
    let out2 = (limb2 & mask) + carry1
    let out3 = (limb3 & mask) + carry2
    let out4 = (limb4 & mask) + carry3

    out1 += out0 >> 51
    out0 &= mask

    return Self(limb0: out0, limb1: out1, limb2: out2, limb3: out3, limb4: out4)
  }

  /// Canonical byte representation modulo 2^255 - 19 (32 bytes little-endian).
  internal func canonicalBytes() -> Data {
    let red = reduced().reduced()
    var elem0 = red.limb0
    var elem1 = red.limb1
    var elem2 = red.limb2
    var elem3 = red.limb3
    var elem4 = red.limb4

    var quotient = (elem0 + 19) >> 51
    quotient = (elem1 + quotient) >> 51
    quotient = (elem2 + quotient) >> 51
    quotient = (elem3 + quotient) >> 51
    quotient = (elem4 + quotient) >> 51

    elem0 += 19 * quotient
    let mask = Self.mask51
    elem1 += elem0 >> 51
    elem0 &= mask
    elem2 += elem1 >> 51
    elem1 &= mask
    elem3 += elem2 >> 51
    elem2 &= mask
    elem4 += elem3 >> 51
    elem3 &= mask
    elem4 &= mask

    return Self.packBytes(
      limb0: elem0,
      limb1: elem1,
      limb2: elem2,
      limb3: elem3,
      limb4: elem4
    )
  }
}

// swiftlint:enable no_magic_numbers
