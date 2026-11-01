// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// Classification of the card's answers to credential updates, driven
/// through `CardOperations` over a scripted channel: accept, count
/// down, blocked, invalidated, and the residual case.
///
/// A change or unblock is addressed under the numbering its
/// `CardPinLengths` was mapped by; a VERIFY leads with the counter-safe
/// reference-numbering probe (S1 v4.2 §3.5.1.1), and a recognised
/// citizen answer resolves the session in one exchange.
@Suite
internal struct CredentialUpdateClassificationTests {
  @Test
  internal func changeSucceedsOnSuccessStatus() throws {
    let channel = ScriptedChannel([
      ("0024001118313233340000000000000000343332310000000000000000", "9000")
    ])
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
      new: new.consumeForSingleTransmission(),
      lengths: .notListed(numbering: .citizen)
    )
    #expect(channel.isExhausted)
  }

  @Test
  internal func changeRejectionCarriesTheRetryCounter() throws {
    let channel = ScriptedChannel([
      ("0024001118313233340000000000000000343332310000000000000000", "63C2")
    ])
    let operations = CardOperations(channel: channel)
    let two = try #require(RetryCount(attemptsRemaining: 2))
    guard
      let current = Pin1(digits: "1234"),
      let new = Pin1(digits: "4321")
    else {
      Issue.record("valid PIN failed to construct")
      return
    }
    do {
      try operations.changePin1(
        current: current.consumeForSingleTransmission(),
        new: new.consumeForSingleTransmission(),
        lengths: .notListed(numbering: .citizen)
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
  internal func unblockAgainstABlockedPukThrowsBlocked() {
    let channel = ScriptedChannel([
      ("002C001118313233343536373800000000343332310000000000000000", "6983")
    ])
    let operations = CardOperations(channel: channel)
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
        new: new.consumeForSingleTransmission(),
        lengths: .notListed(numbering: .citizen)
      )
      Issue.record("expected pinBlocked")
    } catch let error as CardOperationError {
      #expect(error == .pinBlocked)
    } catch {
      Issue.record("unexpected error type")
    }
    #expect(channel.isExhausted)
  }

  @Test
  internal func unblockAgainstAnInvalidatedSlotThrowsInvalidated() {
    let channel = ScriptedChannel([
      ("002C001118313233343536373800000000343332310000000000000000", "6984")
    ])
    let operations = CardOperations(channel: channel)
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
        new: new.consumeForSingleTransmission(),
        lengths: .notListed(numbering: .citizen)
      )
      Issue.record("expected credentialInvalidated")
    } catch let error as CardOperationError {
      #expect(error == .credentialInvalidated)
    } catch {
      Issue.record("unexpected error type")
    }
    #expect(channel.isExhausted)
  }

  @Test
  internal func changeResidualStatusMapsToUpdateFailed() {
    let channel = ScriptedChannel([
      ("0024008218313233343536000000000000363534333231000000000000", "6700")
    ])
    let operations = CardOperations(channel: channel)
    guard
      let current = Pin2(digits: "123456"),
      let new = Pin2(digits: "654321")
    else {
      Issue.record("valid PIN failed to construct")
      return
    }
    do {
      try operations.changePin2(
        current: current.consumeForSingleTransmission(),
        new: new.consumeForSingleTransmission(),
        lengths: .notListed(numbering: .citizen)
      )
      Issue.record("expected credentialUpdateFailed")
    } catch let error as CardOperationError {
      #expect(error == .credentialUpdateFailed(.wrongLength))
    } catch {
      Issue.record("unexpected error type")
    }
    #expect(channel.isExhausted)
  }

  @Test
  internal func verifyPin2AgainstAnUnactivatedSlotThrowsInvalidated() {
    // A never-activated signature slot answers `6984`, which is a real
    // state on the PIN2 path (unlike PIN1, whose floor probe intercepts
    // it before VERIFY).
    let channel = ScriptedChannel([
      ("0020001100", "63C5"),
      ("002000820C313233343536000000000000", "6984"),
    ])
    let operations = CardOperations(channel: channel)
    guard let pin = Pin2(digits: "123456") else {
      Issue.record("valid PIN failed to construct")
      return
    }
    do {
      try operations.verifyPin2(pin.consumeForSingleTransmission())
      Issue.record("expected credentialInvalidated")
    } catch let error as CardOperationError {
      #expect(error == .credentialInvalidated)
    } catch {
      Issue.record("unexpected error type")
    }
    #expect(channel.isExhausted)
  }
}
