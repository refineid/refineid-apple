// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineID

/// The identity line with remote use off speaks of this Mac's reader alone
/// (hierarchy specification §5.2); a card in the reader still shows its
/// holder.
@Suite
internal struct IdentityLineRemoteUseTests {
  internal struct Case: Sendable, CustomTestStringConvertible {
    internal let name: String
    internal let facts: RequesterFacts
    internal let line: IdentityLine

    internal var testDescription: String { name }
  }

  private static let phone = "Alpha iPhone"

  /// Remote use off, nothing here and nothing paired.
  private static let off = RequesterFacts(
    availability: .noCard,
    warnsUnavailableCard: false,
    readerConnected: false,
    cardPresent: false,
    remoteUse: false,
    pairedPhone: nil
  )

  internal static let cases: [Case] = [
    Case(name: "no reader asks for a reader", facts: off, line: .connectReader),
    Case(
      name: "an empty reader asks for the card",
      facts: with { $0.readerConnected = true }, line: .insertCard),
    Case(
      name: "a paired phone is not named",
      facts: with { $0.pairedPhone = phone }, line: .connectReader),
    Case(
      name: "a paired phone is not named beside an empty reader",
      facts: with { facts in
        facts.readerConnected = true
        facts.pairedPhone = phone
      },
      line: .insertCard),
    Case(
      name: "the phone that forgot this computer is not named",
      facts: with { $0.phoneThatForgot = phone }, line: .connectReader),
    Case(
      name: "a local card shows its holder",
      facts: with { facts in
        facts.availability = .ready
        facts.readerConnected = true
        facts.cardPresent = true
      },
      line: .localHolder),
    Case(
      name: "a local card settling shows nothing",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.readerConnected = true
        facts.cardPresent = true
      },
      line: .reading),
  ]

  private static func with(_ change: (inout RequesterFacts) -> Void) -> RequesterFacts {
    var facts = off
    change(&facts)
    return facts
  }

  /// Each combination shows its line.
  @Test(arguments: cases)
  internal func derivesTheLine(_ testCase: Case) {
    #expect(IdentityLine.derive(testCase.facts) == testCase.line)
  }

  /// Turning remote use on brings the pairing prompt beside an empty
  /// reader, and with a pairing the paired phone's line, connecting.
  @Test
  internal func remoteUseOnBringsThePhoneBack() {
    var facts = Self.with { $0.readerConnected = true }
    #expect(IdentityLine.derive(facts) == .insertCard)
    facts.remoteUse = true
    #expect(IdentityLine.derive(facts) == .pairPhone)
    facts.pairedPhone = Self.phone
    #expect(IdentityLine.derive(facts) == .paired(.connecting, phone: Self.phone))
  }
}
