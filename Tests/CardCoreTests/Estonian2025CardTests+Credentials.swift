// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

extension Estonian2025CardTests {
  @Test
  internal func estonian2025ChangeAndSingleCommandUnblockMatchWire() throws {
    let lengths = CardPinLengths.notListed(numbering: .estonian2025)
    let channel = ScriptedChannel([
      ("0024008118" + Self.padZero12Hex("1234") + Self.padZero12Hex("5678"), "9000"),
      ("0024008218" + Self.padZero12Hex("12345") + Self.padZero12Hex("54321"), "9000"),
      ("002C008118" + Self.padZero12Hex("12345678") + Self.padZero12Hex("4321"), "9000"),
      ("002C008218" + Self.padZero12Hex("12345678") + Self.padZero12Hex("98765"), "9000"),
    ])
    let operations = CardOperations(channel: channel, numbering: .estonian2025)
    guard
      let oldPin1 = Pin1(digits: "1234"),
      let newPin1 = Pin1(digits: "5678"),
      let oldPin2 = Pin2(digits: "12345"),
      let newPin2 = Pin2(digits: "54321"),
      let puk1 = Puk(digits: "12345678"),
      let resetPin1 = Pin1(digits: "4321"),
      let puk2 = Puk(digits: "12345678"),
      let resetPin2 = Pin2(digits: "98765")
    else {
      Issue.record("synthetic credentials failed to construct")
      return
    }
    try operations.changePin1(
      current: oldPin1.consumeForSingleTransmission(),
      new: newPin1.consumeForSingleTransmission(),
      lengths: lengths
    )
    try operations.changePin2(
      current: oldPin2.consumeForSingleTransmission(),
      new: newPin2.consumeForSingleTransmission(),
      lengths: lengths
    )
    try operations.unblockPin1(
      puk: puk1.consumeForSingleTransmission(),
      new: resetPin1.consumeForSingleTransmission(),
      lengths: lengths
    )
    try operations.unblockPin2(
      puk: puk2.consumeForSingleTransmission(),
      new: resetPin2.consumeForSingleTransmission(),
      lengths: lengths
    )
    #expect(channel.isExhausted)
  }

  @Test
  internal func estonian2018DocumentNumberRethrowsSecurityNotSatisfiedImmediately() {
    let channel = ScriptedChannel([
      ("00A4000C", "9000"),
      ("00A4020C02D003", "6982"),
      ("00A4000C02D003", "6982"),
    ])
    let operations = CardOperations(channel: channel, numbering: .estonian2018)
    #expect(throws: CardOperationError.selectRejected(.securityNotSatisfied)) {
      _ = try operations.readEstonian2018DocumentNumber()
    }
    #expect(channel.isExhausted)
  }

  @Test
  internal func selectByPathRejectsEmptyAndOversizedPaths() {
    #expect(CommandApdu.selectByPath([]) == nil)
    let oversized = Array(repeating: FileIdentifier.estonianAwpDirectory, count: 128)
    #expect(CommandApdu.selectByPath(oversized) == nil)
  }
}
