// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Decimal spelling of certificate serial numbers.
extension AsicVerification {
  /// The base of a decimal serial number.
  private static let decimalBase = 10

  /// The decimal spelling of zero.
  private static let decimalZero = 0

  /// The decimal spelling of a big-endian unsigned magnitude.
  internal static func decimal(_ magnitude: Data) -> String {
    var digits: [UInt8] = []
    var remaining = Array(magnitude.drop { $0 == 0 })
    while !remaining.isEmpty {
      var carry = 0
      var quotient: [UInt8] = []
      for byte in remaining {
        let value = carry << UInt8.bitWidth | Int(byte)
        let digit = value / Self.decimalBase
        carry = value % Self.decimalBase
        if !quotient.isEmpty || digit != 0 {
          quotient.append(UInt8(digit))
        }
      }
      digits.append(UInt8(carry))
      remaining = quotient
    }
    guard !digits.isEmpty else { return String(Self.decimalZero) }
    return String(digits.reversed().map { digit in Character(String(digit)) })
  }
}
