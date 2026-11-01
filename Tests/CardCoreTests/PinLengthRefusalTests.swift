// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// An entry whose length the card in session does not accept is refused
/// before any command: the scripted channel holds no exchange, so any
/// transmit would be recorded as an issue.
@Suite
internal struct PinLengthRefusalTests {
  /// The card lists PIN 1 up to eight digits.
  private static let shortPin1Maximum = 8
  /// The card lists the PUK from ten digits.
  private static let longPukMinimum = 10

  private static func lengths(
    _ objects: [AuthenticationObjectFixture]
  ) throws -> CardPinLengths {
    let file = AuthenticationObjectFixture.file(objects.map(\.encoded))
    let directory = try #require(AuthenticationObjectDirectory.parse(file))
    return CardPinLengths.mapping(directory, numbering: .citizen)
  }

  private static func digits(_ count: Int) -> String {
    String(repeating: "7", count: count)
  }

  private static func expectRefusal(_ role: CredentialRole, _ error: any Error) {
    #expect(error as? CardOperationError == .pinLengthRefused(role))
  }

  @Test
  internal func aNewPinLongerThanTheCardTakesIsNotSent() throws {
    var pin1 = AuthenticationObjectFixture.citizen(
      reference: FineidValues.pin1Reference, minimum: Pin1.minimumDigitCount)
    pin1.maximum = Self.shortPin1Maximum
    let lengths = try Self.lengths([pin1])
    let channel = ScriptedChannel([])
    let operations = CardOperations(channel: channel)
    guard
      let current = Pin1(digits: Self.digits(Pin1.minimumDigitCount)),
      let new = Pin1(digits: Self.digits(Self.shortPin1Maximum + 1))
    else {
      Issue.record("valid PIN failed to construct")
      return
    }
    do {
      try operations.changePin1(
        current: current.consumeForSingleTransmission(),
        new: new.consumeForSingleTransmission(),
        lengths: lengths)
      Issue.record("expected pinLengthRefused")
    } catch {
      Self.expectRefusal(.pin1, error)
    }
    #expect(channel.isExhausted)
  }

  @Test
  internal func aCurrentPinShorterThanTheFineidBoundIsNotSent() {
    let channel = ScriptedChannel([])
    let operations = CardOperations(channel: channel)
    guard
      let current = Pin2(digits: Self.digits(Pin2.minimumDigitCount)),
      let new = Pin2(digits: Self.digits(CardPinLengths.fineidPin2MinimumDigitCount))
    else {
      Issue.record("valid PIN failed to construct")
      return
    }
    do {
      try operations.changePin2(
        current: current.consumeForSingleTransmission(),
        new: new.consumeForSingleTransmission(),
        lengths: .notListed(numbering: .citizen))
      Issue.record("expected pinLengthRefused")
    } catch {
      Self.expectRefusal(.pin2, error)
    }
    #expect(channel.isExhausted)
  }

  @Test
  internal func aPukShorterThanTheCardTakesIsNotSent() throws {
    let puk = AuthenticationObjectFixture.citizen(
      reference: FineidValues.pukReference, minimum: Self.longPukMinimum)
    let lengths = try Self.lengths([puk])
    let channel = ScriptedChannel([])
    let operations = CardOperations(channel: channel)
    guard
      let code = Puk(digits: Self.digits(Puk.minimumDigitCount)),
      let new = Pin2(digits: Self.digits(CardPinLengths.fineidPin2MinimumDigitCount))
    else {
      Issue.record("valid credential failed to construct")
      return
    }
    do {
      try operations.unblockPin2(
        puk: code.consumeForSingleTransmission(),
        new: new.consumeForSingleTransmission(),
        lengths: lengths)
      Issue.record("expected pinLengthRefused")
    } catch {
      Self.expectRefusal(.puk, error)
    }
    #expect(channel.isExhausted)
  }

  @Test
  internal func aCardAcceptingNoLengthRefusesEveryEntry() throws {
    var pin1 = AuthenticationObjectFixture.citizen(
      reference: FineidValues.pin1Reference, minimum: 1)
    pin1.maximum = Pin1.minimumDigitCount - 1
    let lengths = try Self.lengths([pin1])
    let channel = ScriptedChannel([])
    let operations = CardOperations(channel: channel)
    guard
      let code = Puk(digits: Self.digits(Puk.minimumDigitCount)),
      let new = Pin1(digits: Self.digits(Pin1.minimumDigitCount))
    else {
      Issue.record("valid credential failed to construct")
      return
    }
    do {
      try operations.unblockPin1(
        puk: code.consumeForSingleTransmission(),
        new: new.consumeForSingleTransmission(),
        lengths: lengths)
      Issue.record("expected pinLengthRefused")
    } catch {
      Self.expectRefusal(.pin1, error)
    }
    #expect(channel.isExhausted)
  }
}
