// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RefineID

/// Which line the identity row shows for each combination of facts.
@Suite
internal struct IdentityLineTests {
  internal struct Case: Sendable, CustomTestStringConvertible {
    internal let name: String
    internal let facts: RequesterFacts
    internal let line: IdentityLine

    internal var testDescription: String { name }
  }

  private static let idle = RequesterFacts(
    availability: .noCard,
    warnsUnavailableCard: false,
    readInFlight: false,
    readerConnected: false,
    cardPresent: false,
    phonePresent: false,
    paired: false
  )

  internal static let cases: [Case] = [
    Case(name: "nothing here", facts: idle, line: .connectReader),
    Case(
      name: "empty reader",
      facts: with { $0.readerConnected = true }, line: .insertCard),
    Case(
      name: "empty reader beats a present phone",
      facts: with { facts in
        facts.readerConnected = true
        facts.phonePresent = true
      },
      line: .insertCard),
    Case(
      name: "paired phone off the network",
      facts: with { $0.paired = true }, line: .phoneUnreachable),
    Case(
      name: "empty reader beats an unreachable phone",
      facts: with { facts in
        facts.readerConnected = true
        facts.paired = true
      },
      line: .insertCard),
    Case(
      name: "paired phone here with its card unread",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.paired = true
        facts.phonePresent = true
      },
      line: .phoneConnected),
    Case(
      name: "paired phone present",
      facts: with { facts in
        facts.paired = true
        facts.phonePresent = true
      },
      line: .phoneConnected),
    Case(
      name: "phone present, nothing to do",
      facts: with { $0.phonePresent = true }, line: .phoneConnected),
    Case(
      name: "read in flight",
      facts: with { facts in
        facts.phonePresent = true
        facts.readInFlight = true
      },
      line: .reading),
    Case(
      name: "reader card settling",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.readerConnected = true
        facts.cardPresent = true
      },
      line: .reading),
    Case(
      name: "reader card not ready",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.readerConnected = true
        facts.cardPresent = true
        facts.warnsUnavailableCard = true
      },
      line: .cardNotReady),
    Case(
      name: "phone here, card not read, nothing in flight",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.phonePresent = true
      },
      line: .phoneConnected),
    Case(
      name: "phone here, card not read yet",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.phonePresent = true
        facts.readInFlight = true
      },
      line: .reading),
    Case(
      name: "reader card beats a waiting phone",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.cardPresent = true
        facts.phonePresent = true
      },
      line: .reading),
    Case(
      name: "read in flight beats an empty reader",
      facts: with { facts in
        facts.readerConnected = true
        facts.readInFlight = true
      },
      line: .reading),
    Case(
      name: "a waiting phone beats the card warning",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.phonePresent = true
        facts.warnsUnavailableCard = true
      },
      line: .phoneConnected),
    Case(
      name: "the card warning needs a card",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.phonePresent = true
        facts.readInFlight = true
        facts.warnsUnavailableCard = true
      },
      line: .reading),
    Case(
      name: "identity ready",
      facts: with { facts in
        facts.availability = .ready
        facts.cardPresent = true
      },
      line: .holder),
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
