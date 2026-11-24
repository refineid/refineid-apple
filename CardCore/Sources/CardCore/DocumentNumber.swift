// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A validated Estonian eID printed document number (`XX9999999`).
///
/// The plastic card prints a nine-character document number independently of
/// the chip serial: two uppercase ASCII letters followed by seven ASCII digits
/// (GED24035 section 9 PD7; ID1 Developer Guide 2025 section 6.1). EstEID 2025
/// stores it as plain ASCII in `DF.DD / EF.5007`; EstEID 2018 stores it as a
/// DER TLV (tag `04` OCTET STRING on Cosmo v8, tag `5A` `[APPLICATION 26]` on
/// Cosmo X) in `MF / EF.D003`.
public struct DocumentNumber: Equatable, Hashable, Sendable {
  /// Exact character count of `XX9999999`.
  public static let characterCount = EstonianEidValues.documentNumberCharacterCount

  /// Read cap for plain-ASCII `EF.5007`: one byte past a valid number.
  internal static let probeReadCap = EstonianEidValues.documentNumberProbeCap

  /// Uppercase ASCII letters.
  private static let asciiUppercase = UInt8(ascii: "A")...UInt8(ascii: "Z")

  /// ASCII decimal digits.
  private static let asciiDigits = UInt8(ascii: "0")...UInt8(ascii: "9")

  /// Length of the leading two-byte TLV header (tag + short-form length).
  private static let tlvHeaderLength = 2

  /// The validated printed document number.
  public let value: String

  /// Validates raw ASCII bytes from `EF.5007` against `XX9999999`.
  public init?(asciiBytes: Data) {
    let bytes = Array(asciiBytes)
    guard
      bytes.count == Self.characterCount,
      bytes.prefix(EstonianEidValues.documentNumberLetterPrefixCount).allSatisfy({ byte in
        Self.asciiUppercase.contains(byte)
      }),
      bytes.dropFirst(EstonianEidValues.documentNumberLetterPrefixCount).allSatisfy({ byte in
        Self.asciiDigits.contains(byte)
      }),
      let text = String(bytes: bytes, encoding: .ascii)
    else {
      return nil
    }
    self.value = text
  }

  /// Validates one DER TLV from `EF.D003` (tag `04` or `5A`, short-form length)
  /// and checks its payload against `XX9999999`.
  public init?(tlvBytes: Data) {
    let bytes = Array(tlvBytes)
    guard bytes.count >= Self.tlvHeaderLength else { return nil }
    let tag = bytes[0]
    let lengthByte = bytes[1]
    guard
      tag == EstonianEidValues.documentNumberTagOctetString
        || tag == EstonianEidValues.documentNumberTagApplication26,
      lengthByte <= EstonianEidValues.shortFormDerLengthMax
    else {
      return nil
    }
    let declaredLength = Int(lengthByte)
    guard bytes.count == Self.tlvHeaderLength + declaredLength else {
      return nil
    }
    self.init(asciiBytes: Data(bytes.dropFirst(Self.tlvHeaderLength)))
  }
}
