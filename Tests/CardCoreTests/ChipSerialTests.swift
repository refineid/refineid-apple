// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

@Suite
internal struct ChipSerialTests {
  @Test
  internal func refusesEmpty() {
    #expect(ChipSerial(value: "") == nil)
  }

  @Test
  internal func refusesOversized() {
    let oversized = String(
      repeating: "A",
      count: ChipSerial.maximumLength + 1
    )
    #expect(ChipSerial(value: oversized) == nil)
  }

  @Test
  internal func acceptsMaximumLength() {
    let maximal = String(repeating: "9", count: ChipSerial.maximumLength)
    #expect(ChipSerial(value: maximal) != nil)
  }

  @Test
  internal func refusesNonPrintableAndSpaces() {
    #expect(ChipSerial(value: "ABC 123") == nil)
    #expect(ChipSerial(value: "ABC\n123") == nil)
    #expect(ChipSerial(value: "sarja\u{0000}") == nil)
    #expect(ChipSerial(value: "sarjanumero-ä") == nil)
  }

  @Test
  internal func distinctSerialsDiffer() throws {
    let first = try #require(ChipSerial(value: "9990000001"))
    let second = try #require(ChipSerial(value: "9990000002"))
    #expect(first != second)
  }
}
