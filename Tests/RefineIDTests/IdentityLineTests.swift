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

  /// Remote use on, nothing here and nothing paired.
  private static let idle = RequesterFacts(
    availability: .noCard,
    warnsUnavailableCard: false,
    readerConnected: false,
    cardPresent: false,
    remoteUse: true,
    pairedPhone: nil
  )

  internal static let cases: [Case] = [
    // Remote use on, no card here and no phone paired.
    Case(name: "nothing here asks for a pairing code", facts: idle, line: .pairPhone),
    Case(
      name: "an empty reader, nothing paired, still asks for a pairing code",
      facts: with { $0.readerConnected = true }, line: .pairPhone),
    Case(
      name: "a phone's word without a pairing asks for a pairing code",
      facts: with { $0.phoneCardStatus = noCardReaderAttached }, line: .pairPhone),
    Case(
      name: "an identity left without a pairing asks for a pairing code",
      facts: with { $0.availability = .ready }, line: .pairPhone),
    Case(
      name: "the phone that forgot this computer is named",
      facts: with { $0.phoneThatForgot = phone }, line: .phoneForgot(phone)),
    Case(
      name: "the phone that forgot this computer is named beside an empty reader",
      facts: with { facts in
        facts.readerConnected = true
        facts.phoneThatForgot = phone
      },
      line: .phoneForgot(phone)),

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
      name: "a paired phone offering no identity is connecting",
      facts: with { $0.pairedPhone = phone }, line: .paired(.connecting, phone: phone)),
    Case(
      name: "a paired phone beside an empty reader here is connecting",
      facts: with { facts in
        facts.readerConnected = true
        facts.pairedPhone = phone
      },
      line: .paired(.connecting, phone: phone)),
    Case(
      name: "a paired phone with its card unread is connecting",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.pairedPhone = phone
      },
      line: .paired(.connecting, phone: phone)),
    Case(
      name: "the card warning needs a local card",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.pairedPhone = phone
        facts.warnsUnavailableCard = true
      },
      line: .paired(.connecting, phone: phone)),
    Case(
      name: "a phone holding a card in its reader, the card unread, is connecting",
      facts: with { facts in
        facts.pairedPhone = phone
        facts.phoneCardStatus = cardInReader
      },
      line: .paired(.connecting, phone: phone)),
    Case(
      name: "a phone holding a card in its reader shows the holder",
      facts: with { facts in
        facts.availability = .ready
        facts.pairedPhone = phone
        facts.phoneCardStatus = cardInReader
      },
      line: .paired(.holder, phone: phone)),
    Case(
      name: "a phone's holder shows beside an empty reader here",
      facts: with { facts in
        facts.availability = .ready
        facts.readerConnected = true
        facts.pairedPhone = phone
        facts.phoneCardStatus = cardInReader
      },
      line: .paired(.holder, phone: phone)),
    Case(
      name: "an identity with no word from the phone yet shows the holder",
      facts: with { facts in
        facts.availability = .ready
        facts.pairedPhone = phone
      },
      line: .paired(.holder, phone: phone)),
    Case(
      name: "a phone without a card reader reporting no card keeps the holder",
      facts: with { facts in
        facts.availability = .ready
        facts.pairedPhone = phone
        facts.phoneCardStatus = noCardNoReader
      },
      line: .paired(.holder, phone: phone)),
    Case(
      name: "a phone without a card reader reporting no card, no identity, is connecting",
      facts: with { facts in
        facts.pairedPhone = phone
        facts.phoneCardStatus = noCardNoReader
      },
      line: .paired(.connecting, phone: phone)),
    Case(
      name: "a phone's empty card reader asks for the card",
      facts: with { facts in
        facts.pairedPhone = phone
        facts.phoneCardStatus = noCardReaderAttached
      },
      line: .paired(.phoneReader, phone: phone)),
    Case(
      name: "a phone's empty card reader outranks the identity still in its grace",
      facts: with { facts in
        facts.availability = .ready
        facts.pairedPhone = phone
        facts.phoneCardStatus = noCardReaderAttached
      },
      line: .paired(.phoneReader, phone: phone)),
    Case(
      name: "a phone's empty card reader, its card unread, asks for the card",
      facts: with { facts in
        facts.availability = .cardWithoutIdentity
        facts.pairedPhone = phone
        facts.phoneCardStatus = noCardReaderAttached
      },
      line: .paired(.phoneReader, phone: phone)),
    Case(
      name: "a phone's empty card reader outranks an empty reader here",
      facts: with { facts in
        facts.readerConnected = true
        facts.pairedPhone = phone
        facts.phoneCardStatus = noCardReaderAttached
      },
      line: .paired(.phoneReader, phone: phone)),
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
