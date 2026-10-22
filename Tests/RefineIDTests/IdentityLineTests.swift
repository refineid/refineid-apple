// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import RappEngine
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

  /// The phone's word: no card, a contact reader attached to it.
  private static let noCardReaderAttached = RappCardStatus(card: .absent, reader: .attached)

  /// The phone's word: no card and no reader, as on a phone that reads
  /// cards only over NFC.
  private static let noCardNoReader = RappCardStatus(card: .absent, reader: .absent)

  /// The phone's word: a card in its reader.
  private static let cardInReader = RappCertificateFingerprint(
    certificate: Data("authentication certificate".utf8)
  ).map { RappCardStatus(card: .present($0), reader: .attached) }

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
    Case(name: "nothing here", facts: idle, line: .pairPhone),
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
      line: .connecting),
    Case(
      name: "paired phone present, no card reported yet",
      facts: with { facts in
        facts.pairedPhone = phone
        facts.phonePresent = true
      },
      line: .connecting),
    Case(
      name: "paired phone holds no card, its reader attached",
      facts: with { facts in
        facts.pairedPhone = phone
        facts.phonePresent = true
        facts.phoneCardStatus = noCardReaderAttached
      },
      line: .phoneCard(.insertIntoPhoneReader)),
    Case(
      name: "paired phone holds no card and has no reader",
      facts: with { facts in
        facts.pairedPhone = phone
        facts.phonePresent = true
        facts.phoneCardStatus = noCardNoReader
      },
      line: .phoneCard(.placeOnPhone)),
    Case(
      name: "a phone without a card outranks the identity still in its grace",
      facts: with { facts in
        facts.availability = .ready
        facts.pairedPhone = phone
        facts.phoneCardStatus = noCardReaderAttached
      },
      line: .phoneCard(.insertIntoPhoneReader)),
    Case(
      name: "a phone without a card or a reader outranks the identity still in its grace",
      facts: with { facts in
        facts.availability = .ready
        facts.pairedPhone = phone
        facts.phoneCardStatus = noCardNoReader
      },
      line: .phoneCard(.placeOnPhone)),
    Case(
      name: "a phone without a card, its card unread, asks for the card",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.pairedPhone = phone
        facts.phonePresent = true
        facts.phoneCardStatus = noCardNoReader
      },
      line: .phoneCard(.placeOnPhone)),
    Case(
      name: "a phone holding a card in its reader shows the holder",
      facts: with { facts in
        facts.availability = .ready
        facts.pairedPhone = phone
        facts.phonePresent = true
        facts.phoneCardStatus = cardInReader
      },
      line: .holder),
    Case(
      name: "a phone holding a card in its reader, the card unread, is connecting",
      facts: with { facts in
        facts.pairedPhone = phone
        facts.phonePresent = true
        facts.phoneCardStatus = cardInReader
      },
      line: .connecting),
    Case(
      name: "a reader card here outranks a phone without a card",
      facts: with { facts in
        facts.availability = .ready
        facts.cardPresent = true
        facts.pairedPhone = phone
        facts.phoneCardStatus = noCardReaderAttached
      },
      line: .holder),
    Case(
      name: "an empty reader here outranks a phone without a card",
      facts: with { facts in
        facts.readerConnected = true
        facts.pairedPhone = phone
        facts.phoneCardStatus = noCardReaderAttached
      },
      line: .insertCard),
    Case(
      name: "a phone on the network without a pairing is nothing to show",
      facts: with { $0.phonePresent = true }, line: .pairPhone),
    Case(
      name: "read in flight",
      facts: with { facts in
        facts.phonePresent = true
        facts.readInFlight = true
      },
      line: .connecting),
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
      line: .connecting),
    Case(
      name: "an unpaired phone with the card unread is still connecting",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.phonePresent = true
      },
      line: .connecting),
    Case(
      name: "phone here, card not read yet",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.phonePresent = true
        facts.readInFlight = true
      },
      line: .connecting),
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
      line: .connecting),
    Case(
      name: "a waiting phone beats the card warning",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.pairedPhone = phone
        facts.phonePresent = true
        facts.warnsUnavailableCard = true
      },
      line: .connecting),
    Case(
      name: "the card warning needs a card",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.phonePresent = true
        facts.readInFlight = true
        facts.warnsUnavailableCard = true
      },
      line: .connecting),
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

  /// The phone's reader is named only for no card beside an attached
  /// reader; no card and no reader asks for the card on the phone, and a
  /// present card or no word asks for nothing (RAPP v26.10.22 §8.4 item 6).
  @Test
  internal func phoneCardRequestFollowsCardAndReader() throws {
    let present = try #require(Self.cardInReader)
    #expect(PhoneCardRequest(Self.noCardReaderAttached) == .insertIntoPhoneReader)
    #expect(PhoneCardRequest(Self.noCardNoReader) == .placeOnPhone)
    #expect(PhoneCardRequest(present) == nil)
    #expect(PhoneCardRequest(RappCardStatus(card: present.card, reader: .absent)) == nil)
    #expect(PhoneCardRequest(nil) == nil)
  }
}
