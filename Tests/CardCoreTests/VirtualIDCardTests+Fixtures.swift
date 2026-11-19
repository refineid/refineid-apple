// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
// https://www.apache.org/licenses/LICENSE-2.0

import CardCore
import Testing

/// Checks credential-bearing state without formatting operands in diagnostics.
internal func expectState(
  _ matches: Bool, sourceLocation: SourceLocation
) {
  #expect(matches, "Credential state matches the expected result.", sourceLocation: sourceLocation)
}

internal func expectState(
  _ matches: Bool, context: String, sourceLocation: SourceLocation
) {
  #expect(matches, Comment(rawValue: context), sourceLocation: sourceLocation)
}

internal func expectState(
  _ operation: () throws -> Bool, sourceLocation: SourceLocation
) {
  do {
    expectState(try operation(), sourceLocation: sourceLocation)
  } catch {
    Issue.record("Credential state could not be inspected.", sourceLocation: sourceLocation)
  }
}

extension VirtualIDCardTests {
  private enum FixtureFailure: Error {
    case invalidGeneratedEntry
  }

  private static let firstDecimalDigit: Character = "0"
  private static let secondDecimalDigit: Character = "1"

  private static func changedEntry(from current: String, digitCount: Int) -> String {
    let digit = current.first == firstDecimalDigit ? secondDecimalDigit : firstDecimalDigit
    return String(repeating: String(digit), count: digitCount)
  }

  internal static func changedPin1(from current: String) throws -> String {
    let entry = changedEntry(from: current, digitCount: Pin1.minimumDigitCount)
    guard Pin1(digits: entry) != nil else { throw FixtureFailure.invalidGeneratedEntry }
    return entry
  }

  internal static func changedPin2(from current: String) throws -> String {
    let entry = changedEntry(from: current, digitCount: Pin2.minimumDigitCount)
    guard Pin2(digits: entry) != nil else { throw FixtureFailure.invalidGeneratedEntry }
    return entry
  }
}
