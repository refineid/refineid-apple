// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// Wire vectors and answer classification for the credential commands.
///
/// Citizen vectors follow FINEID S1 v4.2 §3.5; organization vectors
/// follow FINEID S4-2 v4.0 §4.2-4.3 and the Idemia organizational
/// cards specification §4.1.6-4.1.7.
@Suite
internal struct CredentialCommandTests {
  @Test
  internal func verifyPin2MatchesTheWireVector() {
    // 00 20 00 82 0C, then "123456" right-padded with zero bytes to
    // twelve (S1 v4.2 §3.5.2).
    guard let pin = Pin2(digits: "123456") else {
      Issue.record("valid PIN failed to construct")
      return
    }
    let command = CredentialBearingCommand.verifyPin2(
      pin.consumeForSingleTransmission(),
      references: .citizen
    )
    #expect(
      command.intoTransportPayload()
        == WireHex.data("002000820C313233343536000000000000")
    )
  }

  @Test
  internal func organizationVerifyPin1SendsTheTypedLength() {
    // 00 20 00 03, Lc = the typed digit count, no padding: the
    // organization card stores no padding attribute and compares at
    // the typed length (S4-2 v4.0 §4.2; S1 v3.0 §3.5.1.1).
    guard let pin = Pin1(digits: "1234") else {
      Issue.record("valid PIN failed to construct")
      return
    }
    let command = CredentialBearingCommand.verifyPin1(
      pin.consumeForSingleTransmission(),
      references: .organization
    )
    #expect(
      command.intoTransportPayload() == WireHex.data("002000030431323334")
    )
  }

  @Test
  internal func organizationVerifyPin2SendsTheTypedLength() {
    // The PIN SIG form differs only in the reference byte (S4-2 v4.0
    // §4.2).
    guard let pin = Pin2(digits: "123456") else {
      Issue.record("valid PIN failed to construct")
      return
    }
    let command = CredentialBearingCommand.verifyPin2(
      pin.consumeForSingleTransmission(),
      references: .organization
    )
    #expect(
      command.intoTransportPayload()
        == WireHex.data("0020000406313233343536")
    )
  }

  @Test
  internal func changePin1MatchesTheWireVector() {
    // 00 24 00 11 18, then the current and the new PIN each padded to
    // twelve (S1 v4.2 §3.5.3).
    guard
      let current = Pin1(digits: "1234"),
      let new = Pin1(digits: "4321")
    else {
      Issue.record("valid PIN failed to construct")
      return
    }
    let command = CredentialBearingCommand.changePin1(
      current: current.consumeForSingleTransmission(),
      new: new.consumeForSingleTransmission(),
      references: .citizen
    )
    #expect(
      command.intoTransportPayload()
        == WireHex.data(
          "0024001118313233340000000000000000343332310000000000000000")
    )
  }

  @Test
  internal func changePin2MatchesTheWireVector() {
    // The PIN2 form differs from `changePin1` only in the reference
    // byte (S1 v4.2 §3.5.3).
    guard
      let current = Pin2(digits: "123456"),
      let new = Pin2(digits: "654321")
    else {
      Issue.record("valid PIN failed to construct")
      return
    }
    let command = CredentialBearingCommand.changePin2(
      current: current.consumeForSingleTransmission(),
      new: new.consumeForSingleTransmission(),
      references: .citizen
    )
    #expect(
      command.intoTransportPayload()
        == WireHex.data(
          "0024008218313233343536000000000000363534333231000000000000")
    )
  }

  @Test
  internal func organizationChangePin1SendsBothBare() {
    // 00 24 00 03, Lc = current + new at their typed lengths, both
    // bare (Idemia organizational cards specification §4.1.7).
    guard
      let current = Pin1(digits: "1234"),
      let new = Pin1(digits: "4321")
    else {
      Issue.record("valid PIN failed to construct")
      return
    }
    let command = CredentialBearingCommand.changePin1(
      current: current.consumeForSingleTransmission(),
      new: new.consumeForSingleTransmission(),
      references: .organization
    )
    #expect(
      command.intoTransportPayload()
        == WireHex.data("00240003083132333434333231")
    )
  }

  @Test
  internal func unblockPin1MatchesTheWireVector() {
    // 00 2C 00 11 18, then the PUK and the new PIN each padded to
    // twelve (S1 v4.2 §3.5.4).
    guard
      let puk = Puk(digits: "12345678"),
      let new = Pin1(digits: "4321")
    else {
      Issue.record("valid credential failed to construct")
      return
    }
    let command = CredentialBearingCommand.unblockPin1(
      puk: puk.consumeForSingleTransmission(),
      new: new.consumeForSingleTransmission(),
      references: .citizen
    )
    #expect(
      command.intoTransportPayload()
        == WireHex.data(
          "002C001118313233343536373800000000343332310000000000000000")
    )
  }

  @Test
  internal func unblockPin1SendsATwelveDigitPukUnpadded() {
    // A PUK at the stored length fills its block (S1 v4.2 §3.5.4).
    guard
      let puk = Puk(digits: "490712345678"),
      let new = Pin1(digits: "4907")
    else {
      Issue.record("valid credential failed to construct")
      return
    }
    let command = CredentialBearingCommand.unblockPin1(
      puk: puk.consumeForSingleTransmission(),
      new: new.consumeForSingleTransmission(),
      references: .citizen
    )
    #expect(
      command.intoTransportPayload()
        == WireHex.data(
          "002C001118343930373132333435363738343930370000000000000000")
    )
  }

  @Test
  internal func unblockPin2MatchesTheWireVector() {
    // The PIN2 form differs from `unblockPin1` only in the target
    // reference byte (S1 v4.2 §3.5.4).
    guard
      let puk = Puk(digits: "12345678"),
      let new = Pin2(digits: "654321")
    else {
      Issue.record("valid credential failed to construct")
      return
    }
    let command = CredentialBearingCommand.unblockPin2(
      puk: puk.consumeForSingleTransmission(),
      new: new.consumeForSingleTransmission(),
      references: .citizen
    )
    #expect(
      command.intoTransportPayload()
        == WireHex.data(
          "002C008218313233343536373800000000363534333231000000000000")
    )
  }

  @Test
  internal func organizationUnblockVerifiesTheCredentialItself() {
    // 00 20 00 12, Lc = typed length: the unblock credential is its
    // own security data object on the organization card (S4-2 v4.0
    // §4.3.2).
    guard let puk = Puk(digits: "12345678") else {
      Issue.record("valid credential failed to construct")
      return
    }
    let command = CredentialBearingCommand.verifyUnblockCredential(
      puk.consumeForSingleTransmission(),
      references: .organization
    )
    #expect(
      command.intoTransportPayload()
        == WireHex.data("00200012083132333435363738")
    )
  }

  @Test
  internal func organizationResetCarriesOnlyTheNewPin() {
    // 00 2C 02 03, Lc = the new PIN's typed length: P1 02 means the
    // unblock credential was verified beforehand and only the new
    // reference data rides here (Idemia organizational cards
    // specification §4.1.6).
    guard let new = Pin1(digits: "4321") else {
      Issue.record("valid PIN failed to construct")
      return
    }
    let command = CredentialBearingCommand.resetPin1AfterVerifiedUnblock(
      new: new.consumeForSingleTransmission(),
      references: .organization
    )
    #expect(
      command.intoTransportPayload() == WireHex.data("002C02030434333231")
    )
  }
}
