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

  private static let phone = "Alpha iPhone"

  private static let idle = RequesterFacts(
    availability: .noCard,
    warnsUnavailableCard: false,
    readInFlight: false,
    readerConnected: false,
    cardPresent: false,
    phonePresent: false,
    pairedPhone: nil
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
      facts: with { $0.pairedPhone = phone }, line: .empty),
    Case(
      name: "empty reader beats an unreachable phone",
      facts: with { facts in
        facts.readerConnected = true
        facts.pairedPhone = phone
      },
      line: .insertCard),
    Case(
      name: "paired phone here with its card unread",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.pairedPhone = phone
        facts.phonePresent = true
      },
      line: .phoneConnected(phone)),
    Case(
      name: "paired phone present",
      facts: with { facts in
        facts.pairedPhone = phone
        facts.phonePresent = true
      },
      line: .phoneConnected(phone)),
    Case(
      name: "a phone on the network without a pairing is nothing to show",
      facts: with { $0.phonePresent = true }, line: .connectReader),
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
        facts.pairedPhone = phone
        facts.phonePresent = true
      },
      line: .phoneConnected(phone)),
    Case(
      name: "an unpaired phone with the card unread is still a read",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.phonePresent = true
      },
      line: .reading),
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
        facts.pairedPhone = phone
        facts.phonePresent = true
        facts.warnsUnavailableCard = true
      },
      line: .phoneConnected(phone)),
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

  /// Only a connected phone waits to show; the name, instructions and
  /// errors show at once.
  @Test
  internal func onlyAConnectedPhoneWaitsToShow() {
    #expect(IdentityLine.phoneConnected(Self.phone).waitsBeforeShowing)
    let immediate: [IdentityLine] = [
      .cardNotReady, .connectReader, .empty, .holder, .insertCard, .phoneForgot(Self.phone),
      .reading,
    ]
    #expect(immediate.allSatisfy { !$0.waitsBeforeShowing })
  }
}
