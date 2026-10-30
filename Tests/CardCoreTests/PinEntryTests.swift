// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

/// The holder's PIN entries: validated once at the text-field border, kept
/// in zeroizing memory, and issuing a fresh single-use PIN per card command.
@Suite
internal struct PinEntryTests {
  private static let digits = "123456"
  private static let otherDigits = "654321"
  private static let serialValue = "9990000001"

  @Test
  internal func pin1EntryAcceptsExactlyWhatPin1Accepts() {
    let shortest = String(repeating: "7", count: Pin1.minimumDigitCount)
    let longest = String(repeating: "7", count: Pin1.maximumDigitCount)
    let tooShort = String(repeating: "7", count: Pin1.minimumDigitCount - 1)
    let tooLong = String(repeating: "7", count: Pin1.maximumDigitCount + 1)
    #expect(Pin1Entry(digits: shortest) != nil)
    #expect(Pin1Entry(digits: longest) != nil)
    #expect(Pin1Entry(digits: tooShort) == nil)
    #expect(Pin1Entry(digits: tooLong) == nil)
    #expect(Pin1Entry(digits: "") == nil)
    #expect(Pin1Entry(digits: "12a4") == nil)
  }

  @Test
  internal func pin2EntryAcceptsExactlyWhatPin2Accepts() {
    let shortest = String(repeating: "7", count: Pin2.minimumDigitCount)
    let longest = String(repeating: "7", count: Pin2.maximumDigitCount)
    let tooShort = String(repeating: "7", count: Pin2.minimumDigitCount - 1)
    let tooLong = String(repeating: "7", count: Pin2.maximumDigitCount + 1)
    #expect(Pin2Entry(digits: shortest) != nil)
    #expect(Pin2Entry(digits: longest) != nil)
    #expect(Pin2Entry(digits: tooShort) == nil)
    #expect(Pin2Entry(digits: tooLong) == nil)
    #expect(Pin2Entry(digits: "") == nil)
    #expect(Pin2Entry(digits: "12a456") == nil)
  }

  @Test
  internal func pin1EntryIssuesTheEnteredDigitsEveryTime() throws {
    let serial = try #require(ChipSerial(value: Self.serialValue))
    let entry = try #require(Pin1Entry(digits: Self.digits))
    guard let typed = Pin1(digits: Self.digits) else {
      Issue.record("valid PIN failed to construct")
      return
    }
    let expected = typed.fingerprint(boundTo: serial)
    let first = entry.issue()
    let second = entry.issue()
    #expect(first.fingerprint(boundTo: serial) == expected)
    #expect(second.fingerprint(boundTo: serial) == expected)
    _ = first.consumeForSingleTransmission()
    // Consuming one issued PIN leaves the entry able to issue the next.
    #expect(entry.issue().fingerprint(boundTo: serial) == expected)
  }

  @Test
  internal func pin2EntryIssuesTheEnteredDigitsEveryTime() throws {
    let serial = try #require(ChipSerial(value: Self.serialValue))
    let entry = try #require(Pin2Entry(digits: Self.digits))
    guard let typed = Pin2(digits: Self.digits) else {
      Issue.record("valid PIN failed to construct")
      return
    }
    let expected = typed.fingerprint(boundTo: serial)
    let first = entry.issue()
    #expect(first.fingerprint(boundTo: serial) == expected)
    _ = first.consumeForSingleTransmission()
    #expect(entry.issue().fingerprint(boundTo: serial) == expected)
  }

  @Test
  internal func sessionFingerprintSeparatesDigitsAndRoles() throws {
    let pin1 = try #require(Pin1Entry(digits: Self.digits))
    let samePin1 = try #require(Pin1Entry(digits: Self.digits))
    let otherPin1 = try #require(Pin1Entry(digits: Self.otherDigits))
    let pin2 = try #require(Pin2Entry(digits: Self.digits))
    #expect(pin1.sessionFingerprint() == samePin1.sessionFingerprint())
    #expect(pin1.sessionFingerprint() != otherPin1.sessionFingerprint())
    #expect(pin1.sessionFingerprint() != pin2.sessionFingerprint())
  }

  @Test
  internal func sessionFingerprintDiffersFromCardBoundFingerprint() throws {
    let serial = try #require(ChipSerial(value: Self.serialValue))
    let entry = try #require(Pin1Entry(digits: Self.digits))
    #expect(entry.sessionFingerprint() != entry.issue().fingerprint(boundTo: serial))
  }

  @Test
  internal func entriesReflectAsEmptyMirrors() throws {
    let pin1 = try #require(Pin1Entry(digits: Self.digits))
    let pin2 = try #require(Pin2Entry(digits: Self.otherDigits))
    #expect(Mirror(reflecting: pin1).children.isEmpty)
    #expect(Mirror(reflecting: pin2).children.isEmpty)
    #expect(!String(describing: pin1).contains(Self.digits))
    #expect(!String(describing: pin2).contains(Self.otherDigits))
  }
}
