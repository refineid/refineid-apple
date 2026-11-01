// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

@Suite
internal struct StatusWordTests {
  @Test
  internal func classifiesEveryModeledWord() {
    #expect(WireHex.statusWord("9000") == .success)
    #expect(WireHex.statusWord("6282") == .endOfFile)
    #expect(WireHex.statusWord("6300") == .authenticationFailed)
    #expect(WireHex.statusWord("6700") == .wrongLength)
    #expect(WireHex.statusWord("6982") == .securityNotSatisfied)
    #expect(WireHex.statusWord("6983") == .authenticationBlocked)
    #expect(WireHex.statusWord("6984") == .referenceDataInvalidated)
    #expect(WireHex.statusWord("6985") == .conditionsNotSatisfied)
    #expect(WireHex.statusWord("6988") == .smDataObjectsIncorrect)
    #expect(WireHex.statusWord("6A82") == .fileNotFound)
    #expect(WireHex.statusWord("6A88") == .referenceDataNotFound)
  }

  @Test
  internal func retryCounterFamilyCarriesTheNibble() throws {
    let five = try #require(RetryCount(attemptsRemaining: 5))
    let zero = try #require(RetryCount(attemptsRemaining: 0))
    let fifteen = try #require(RetryCount(attemptsRemaining: 15))

    #expect(WireHex.statusWord("63C5") == .pinIncorrect(remaining: five))
    #expect(WireHex.statusWord("63C0") == .pinIncorrect(remaining: zero))
    #expect(WireHex.statusWord("63CF") == .pinIncorrect(remaining: fifteen))
  }

  @Test
  internal func responseAvailableFamilyCarriesTheCount() {
    #expect(WireHex.statusWord("6125") == .responseAvailable(count: 37))
    #expect(WireHex.statusWord("6100") == .responseAvailable(count: 0))
    #expect(WireHex.statusWord("61FF") == .responseAvailable(count: 255))
  }

  @Test
  internal func unknownWordsStayUnknown() {
    let unknown = WireHex.statusWord("1234")
    switch unknown {
    case .other(let value):
      #expect(value == UInt16(4_660))

    default:
      Issue.record("unknown status word must classify as other")
    }
  }

  @Test
  internal func encodedRoundTripsEveryClassification() {
    let vectors = [
      "9000", "6282", "6300", "6700", "6982", "6983", "6984", "6988",
      "6A82", "6A88", "63C0", "63C5", "63CF", "1234", "6100", "6125",
    ]
    for vector in vectors {
      let word = WireHex.statusWord(vector)
      let expected = Array(WireHex.data(vector))
      let reencoded = word.encoded
      #expect(
        reencoded == UInt16(expected[0]) << 8 | UInt16(expected[1]),
        "round trip failed for \(vector)"
      )
    }
  }
}
