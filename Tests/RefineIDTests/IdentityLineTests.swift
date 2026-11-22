// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import RappRequester
import Testing

/// Which line the identity row shows for the card in this computer's reader,
/// and which reader state it asks for; the phone's cases are in
/// ``IdentityLinePhoneTests``.
@Suite
internal struct IdentityLineTests {
  internal struct Case: Sendable, CustomTestStringConvertible {
    internal let name: String
    internal let facts: RequesterFacts
    internal let line: IdentityLine

    internal var testDescription: String { name }
  }

  /// Nothing here: no card, no reader.
  private static let idle = RequesterFacts(
    availability: .noCard,
    warnsUnavailableCard: false,
    readerConnected: false,
    cardPresent: false
  )

  internal static let cases: [Case] = [
    Case(name: "no reader asks for a reader", facts: idle, line: .connectReader),
    Case(
      name: "an empty reader asks for the card",
      facts: with { $0.readerConnected = true }, line: .insertCard),
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
    Case(
      name: "a local card not ready warns",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.readerConnected = true
        facts.cardPresent = true
        facts.warnsUnavailableCard = true
      },
      line: .cardNotReady),
    Case(
      name: "a card settling without a reader still reads as settling",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.cardPresent = true
      },
      line: .reading),
    Case(
      name: "a card only on the reader's antenna asks for the contact slot",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.readerConnected = true
        facts.cardPresent = true
        facts.cardOnReaderAntenna = true
      },
      line: .cardOnReaderAntenna),
    Case(
      name: "the antenna's card outranks the settle warning",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.readerConnected = true
        facts.cardPresent = true
        facts.cardOnReaderAntenna = true
        facts.warnsUnavailableCard = true
      },
      line: .cardOnReaderAntenna),
    Case(
      name: "a ready holder outranks the antenna presentation",
      facts: with { facts in
        facts.availability = .ready
        facts.readerConnected = true
        facts.cardPresent = true
        facts.cardOnReaderAntenna = true
      },
      line: .localHolder),
    Case(
      name: "an antenna fact without a present card changes nothing",
      facts: with { $0.cardOnReaderAntenna = true }, line: .connectReader),
  ]

  private static func with(_ change: (inout RequesterFacts) -> Void) -> RequesterFacts {
    var facts = idle
    change(&facts)
    return facts
  }

  /// Each combination shows its line.
  @Test(arguments: cases)
  internal func derivesTheLine(_ testCase: Case) {
    #expect(IdentityLine.derive(testCase.facts) == testCase.line)
  }
}
