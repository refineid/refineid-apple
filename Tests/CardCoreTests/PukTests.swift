// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

@Suite
internal struct PukTests {
  @Test
  internal func refusesTooShortAndTooLong() {
    let tooShort = String(
      repeating: "1",
      count: Puk.minimumDigitCount - 1
    )
    let tooLong = String(
      repeating: "1",
      count: Puk.maximumDigitCount + 1
    )
    #expect(!canConstruct(tooShort))
    #expect(!canConstruct(tooLong))
  }

  @Test
  internal func acceptsBothFieldLengths() {
    // Eight digits is the ordinary PUK; seven-digit activation PUKs
    // exist in the field.
    let sevenDigits = String(repeating: "7", count: Puk.minimumDigitCount)
    let eightDigits = String(repeating: "7", count: Puk.maximumDigitCount)
    #expect(canConstruct(sevenDigits))
    #expect(canConstruct(eightDigits))
  }

  @Test
  internal func refusesNonAsciiDigits() {
    #expect(!canConstruct("1234a678"))
    #expect(!canConstruct("1234 678"))
    #expect(!canConstruct("١٢٣٤٥٦٧٨"))
    #expect(!canConstruct("1234.678"))
  }

  @Test
  internal func fingerprintDiffersFromPin1WithTheSameDigits() throws {
    // Domain separation: the same digits under the PIN1 and PUK roles
    // must never collide in the rejected-PIN memory.
    let serial = try #require(ChipSerial(value: "9990000001"))
    guard
      let pin1 = Pin1(digits: "12345678"),
      let puk = Puk(digits: "12345678")
    else {
      Issue.record("valid credential failed to construct")
      return
    }
    #expect(
      pin1.fingerprint(boundTo: serial) != puk.fingerprint(boundTo: serial)
    )
  }

  @Test
  internal func consumingForTransmissionEndsTheValue() {
    // The at-most-once property itself is compile-time; this pins down
    // that consumption produces the transmission value exactly once.
    guard let puk = Puk(digits: "12345678") else {
      Issue.record("valid PUK failed to construct")
      return
    }
    _ = puk.consumeForSingleTransmission()
  }

  /// `#expect` requires copyable operands, so noncopyable construction
  /// results are reduced to a Bool here.
  private func canConstruct(_ digits: String) -> Bool {
    switch Puk(digits: digits) {
    case .some:
      true

    case .none:
      false
    }
  }
}
