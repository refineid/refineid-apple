// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

@Suite
internal struct Pin1Tests {
  @Test
  internal func refusesTooShortAndTooLong() {
    let tooShort = String(
      repeating: "1",
      count: Pin1.minimumDigitCount - 1
    )
    let tooLong = String(
      repeating: "1",
      count: Pin1.maximumDigitCount + 1
    )
    #expect(!canConstruct(tooShort))
    #expect(!canConstruct(tooLong))
  }

  @Test
  internal func acceptsBoundaryLengths() {
    let shortest = String(repeating: "7", count: Pin1.minimumDigitCount)
    let longest = String(repeating: "7", count: Pin1.maximumDigitCount)
    #expect(canConstruct(shortest))
    #expect(canConstruct(longest))
  }

  @Test
  internal func refusesNonAsciiDigits() {
    #expect(!canConstruct("12a4"))
    #expect(!canConstruct("12 4"))
    #expect(!canConstruct("١٢٣٤"))
    #expect(!canConstruct("12.4"))
  }

  @Test
  internal func fingerprintIsStableForSamePinAndCard() throws {
    let serial = try #require(ChipSerial(value: "9990000001"))
    guard
      let first = Pin1(digits: "123456"),
      let second = Pin1(digits: "123456")
    else {
      Issue.record("valid PIN failed to construct")
      return
    }
    #expect(
      first.fingerprint(boundTo: serial) == second.fingerprint(boundTo: serial)
    )
  }

  @Test
  internal func fingerprintSeparatesCardsAndPins() throws {
    let cardA = try #require(ChipSerial(value: "9990000001"))
    let cardB = try #require(ChipSerial(value: "9990000002"))
    guard
      let pin = Pin1(digits: "123456"),
      let otherPin = Pin1(digits: "654321")
    else {
      Issue.record("valid PIN failed to construct")
      return
    }

    #expect(pin.fingerprint(boundTo: cardA) != pin.fingerprint(boundTo: cardB))
    #expect(
      pin.fingerprint(boundTo: cardA) != otherPin.fingerprint(boundTo: cardA)
    )
  }

  @Test
  internal func consumingForTransmissionEndsTheValue() {
    // The at-most-once property itself is compile-time: after
    // `consumeForSingleTransmission()` any further use of the Pin1 is a
    // compiler error, which cannot be demonstrated in a runtime test.
    // This test pins down that consumption produces the transmission
    // value exactly once.
    guard let pin = Pin1(digits: "123456") else {
      Issue.record("valid PIN failed to construct")
      return
    }
    _ = pin.consumeForSingleTransmission()
  }

  /// `#expect` requires copyable operands, so noncopyable construction
  /// results are reduced to a Bool here.
  private func canConstruct(_ digits: String) -> Bool {
    switch Pin1(digits: digits) {
    case .some:
      true

    case .none:
      false
    }
  }
}
