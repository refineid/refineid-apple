// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// The credential flows on the organization card, driven through
/// `CardOperations` over a scripted channel: bare typed-length blocks
/// under the FINEID S4-2 v4.0 §4.2 numbering, and the two-command
/// unblock (S4-2 v4.0 §4.3.2; Idemia organizational cards
/// specification §4.1.6-4.1.7).
@Suite
internal struct OrganizationCredentialTests {
  /// The probe pair every unresolved flow leads with on an
  /// organization card (S1 v4.2 §3.5.1.1, counter-safe).
  private static let resolution: [(String, String)] = [
    ("0020001100", "6A88"),
    ("0020000300", "63C5"),
  ]

  @Test
  internal func verifyPin1SendsTheBareTypedBlock() throws {
    let channel = ScriptedChannel(
      Self.resolution + [("002000030431323334", "9000")]
    )
    let operations = CardOperations(channel: channel)
    guard let pin = Pin1(digits: "1234") else {
      Issue.record("valid PIN failed to construct")
      return
    }
    try operations.verifyPin1(pin.consumeForSingleTransmission())
    #expect(channel.isExhausted)
  }

  @Test
  internal func changePin1SendsBothBlocksBare() throws {
    let channel = ScriptedChannel(
      Self.resolution + [("00240003083132333434333231", "9000")]
    )
    let operations = CardOperations(channel: channel)
    guard
      let current = Pin1(digits: "1234"),
      let new = Pin1(digits: "4321")
    else {
      Issue.record("valid PIN failed to construct")
      return
    }
    try operations.changePin1(
      current: current.consumeForSingleTransmission(),
      new: new.consumeForSingleTransmission()
    )
    #expect(channel.isExhausted)
  }

  @Test
  internal func unblockRunsTheTwoCommandSequence() throws {
    // VERIFY of the unblock credential as its own object, then RESET
    // RETRY COUNTER with P1 02 carrying only the new PIN.
    let channel = ScriptedChannel(
      Self.resolution + [
        ("00200012083132333435363738", "9000"),
        ("002C02030434333231", "9000"),
      ]
    )
    let operations = CardOperations(channel: channel)
    guard
      let puk = Puk(digits: "12345678"),
      let new = Pin1(digits: "4321")
    else {
      Issue.record("valid credential failed to construct")
      return
    }
    try operations.unblockPin1(
      puk: puk.consumeForSingleTransmission(),
      new: new.consumeForSingleTransmission()
    )
    #expect(channel.isExhausted)
  }

  @Test
  internal func unblockStopsWhenTheCodeIsRefused() throws {
    // A refused code ends the flow before the reset: the exhausted
    // script proves no second command went out.
    let channel = ScriptedChannel(
      Self.resolution + [("00200012083132333435363738", "63C2")]
    )
    let operations = CardOperations(channel: channel)
    let two = try #require(RetryCount(attemptsRemaining: 2))
    guard
      let puk = Puk(digits: "12345678"),
      let new = Pin1(digits: "4321")
    else {
      Issue.record("valid credential failed to construct")
      return
    }
    do {
      try operations.unblockPin1(
        puk: puk.consumeForSingleTransmission(),
        new: new.consumeForSingleTransmission()
      )
      Issue.record("expected pinRejected")
    } catch let error as CardOperationError {
      #expect(error == .pinRejected(remaining: two))
    } catch {
      Issue.record("unexpected error type")
    }
    #expect(channel.isExhausted)
  }

  @Test
  internal func unblockPin2TargetsThePinSigObject() throws {
    let channel = ScriptedChannel(
      Self.resolution + [
        ("00200012083132333435363738", "9000"),
        ("002C020406363534333231", "9000"),
      ]
    )
    let operations = CardOperations(channel: channel)
    guard
      let puk = Puk(digits: "12345678"),
      let new = Pin2(digits: "654321")
    else {
      Issue.record("valid credential failed to construct")
      return
    }
    try operations.unblockPin2(
      puk: puk.consumeForSingleTransmission(),
      new: new.consumeForSingleTransmission()
    )
    #expect(channel.isExhausted)
  }

  @Test
  internal func twelveDigitPin1IsSentUnpadded() throws {
    // The organization card takes PIN 1 at 4-12 digits, like the
    // citizen card; the block is the twelve typed digits, Lc twelve.
    let channel = ScriptedChannel(
      Self.resolution + [("002000030C313233343536373839303132", "9000")]
    )
    let operations = CardOperations(channel: channel)
    guard let pin = Pin1(digits: "123456789012") else {
      Issue.record("valid PIN failed to construct")
      return
    }
    try operations.verifyPin1(pin.consumeForSingleTransmission())
    #expect(channel.isExhausted)
  }

  @Test
  internal func twelveDigitPin2IsSentUnpadded() throws {
    // PIN 2 at 6-12 digits, under the PIN SIG reference.
    let channel = ScriptedChannel(
      Self.resolution + [("002000040C313233343536373839303132", "9000")]
    )
    let operations = CardOperations(channel: channel)
    guard let pin = Pin2(digits: "123456789012") else {
      Issue.record("valid PIN failed to construct")
      return
    }
    try operations.verifyPin2(pin.consumeForSingleTransmission())
    #expect(channel.isExhausted)
  }

  @Test
  internal func thirteenDigitPinIsRefusedBeforeAnyCommand() {
    // Thirteen digits never become a PIN, so no command can carry them.
    let thirteen = String(repeating: "1", count: Pin1.maximumDigitCount + 1)
    #expect(Pin1Entry(digits: thirteen) == nil)
    #expect(Pin2Entry(digits: thirteen) == nil)
  }
}
