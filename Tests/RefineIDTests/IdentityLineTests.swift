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
    // No card here and no phone paired.
    Case(name: "nothing here asks for a pairing code", facts: idle, line: .pairPhone),
    Case(
      name: "an empty reader, nothing paired",
      facts: with { $0.readerConnected = true }, line: .insertCard),
    Case(
      name: "a phone on the network without a pairing asks for a pairing code",
      facts: with { $0.phonePresent = true }, line: .pairPhone),
    Case(
      name: "a forgotten pairing's phone in sight asks for a pairing code",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.phonePresent = true
        facts.readInFlight = true
      },
      line: .pairPhone),
    Case(
      name: "the phone that forgot this computer is named",
      facts: with { $0.phoneThatForgot = phone }, line: .phoneForgot(phone)),
    Case(
      name: "an empty reader beats the phone that forgot this computer",
      facts: with { facts in
        facts.readerConnected = true
        facts.phoneThatForgot = phone
      },
      line: .insertCard),

    // A card in this Mac's reader.
    Case(
      name: "a local card shows its holder",
      facts: with { facts in
        facts.availability = .ready
        facts.readerConnected = true
        facts.cardPresent = true
      },
      line: .localHolder),
    Case(
      name: "a local card overrides a paired phone holding a card",
      facts: with { facts in
        facts.availability = .ready
        facts.readerConnected = true
        facts.cardPresent = true
        facts.pairedPhone = phone
        facts.phonePresent = true
        facts.phoneCardStatus = cardInReader
      },
      line: .localHolder),
    Case(
      name: "a local card overrides a paired phone without a card",
      facts: with { facts in
        facts.availability = .ready
        facts.cardPresent = true
        facts.pairedPhone = phone
        facts.phoneCardStatus = noCardReaderAttached
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
      name: "a local card settling overrides a waiting phone",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.cardPresent = true
        facts.pairedPhone = phone
        facts.phonePresent = true
        facts.readInFlight = true
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

    // A paired phone, no card here.
    Case(
      name: "a paired phone out of sight names the phone alone",
      facts: with { $0.pairedPhone = phone }, line: .paired(.away, phone: phone)),
    Case(
      name: "a paired phone out of sight beside an empty reader asks for the card here",
      facts: with { facts in
        facts.readerConnected = true
        facts.pairedPhone = phone
      },
      line: .paired(.insertCard, phone: phone)),
    Case(
      name: "a paired phone present, no card reported yet, is connecting",
      facts: with { facts in
        facts.pairedPhone = phone
        facts.phonePresent = true
      },
      line: .paired(.connecting, phone: phone)),
    Case(
      name: "a paired phone here with its card unread is connecting",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.pairedPhone = phone
        facts.phonePresent = true
      },
      line: .paired(.connecting, phone: phone)),
    Case(
      name: "a read in flight is connecting",
      facts: with { facts in
        facts.pairedPhone = phone
        facts.readInFlight = true
      },
      line: .paired(.connecting, phone: phone)),
    Case(
      name: "a read in flight beats an empty reader",
      facts: with { facts in
        facts.readerConnected = true
        facts.pairedPhone = phone
        facts.readInFlight = true
      },
      line: .paired(.connecting, phone: phone)),
    Case(
      name: "the card warning needs a local card",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.pairedPhone = phone
        facts.phonePresent = true
        facts.warnsUnavailableCard = true
      },
      line: .paired(.connecting, phone: phone)),
    Case(
      name: "a paired phone holds no card, its reader attached",
      facts: with { facts in
        facts.pairedPhone = phone
        facts.phonePresent = true
        facts.phoneCardStatus = noCardReaderAttached
      },
      line: .paired(.phoneCard(.insertIntoPhoneReader), phone: phone)),
    Case(
      name: "a paired phone holds no card and has no reader",
      facts: with { facts in
        facts.pairedPhone = phone
        facts.phonePresent = true
        facts.phoneCardStatus = noCardNoReader
      },
      line: .paired(.phoneCard(.placeOnPhone), phone: phone)),
    Case(
      name: "a phone without a card outranks the identity still in its grace",
      facts: with { facts in
        facts.availability = .ready
        facts.pairedPhone = phone
        facts.phoneCardStatus = noCardReaderAttached
      },
      line: .paired(.phoneCard(.insertIntoPhoneReader), phone: phone)),
    Case(
      name: "a phone without a card or a reader outranks the identity still in its grace",
      facts: with { facts in
        facts.availability = .ready
        facts.pairedPhone = phone
        facts.phoneCardStatus = noCardNoReader
      },
      line: .paired(.phoneCard(.placeOnPhone), phone: phone)),
    Case(
      name: "a phone without a card, its card unread, asks for the card",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.pairedPhone = phone
        facts.phonePresent = true
        facts.phoneCardStatus = noCardNoReader
      },
      line: .paired(.phoneCard(.placeOnPhone), phone: phone)),
    Case(
      name: "an empty reader here outranks a phone without a card",
      facts: with { facts in
        facts.readerConnected = true
        facts.pairedPhone = phone
        facts.phoneCardStatus = noCardReaderAttached
      },
      line: .paired(.insertCard, phone: phone)),
    Case(
      name: "a phone holding a card in its reader shows the holder",
      facts: with { facts in
        facts.availability = .ready
        facts.pairedPhone = phone
        facts.phonePresent = true
        facts.phoneCardStatus = cardInReader
      },
      line: .paired(.holder, phone: phone)),
    Case(
      name: "a phone's holder shows beside an empty reader here",
      facts: with { facts in
        facts.availability = .ready
        facts.readerConnected = true
        facts.pairedPhone = phone
        facts.phonePresent = true
        facts.phoneCardStatus = cardInReader
      },
      line: .paired(.holder, phone: phone)),
    Case(
      name: "a phone holding a card in its reader, the card unread, is connecting",
      facts: with { facts in
        facts.pairedPhone = phone
        facts.phonePresent = true
        facts.phoneCardStatus = cardInReader
      },
      line: .paired(.connecting, phone: phone)),
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
