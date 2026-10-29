// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import RappEngine
import Testing

@testable import RefineIDTestHost

/// The custodian tells every open session its card and its card reader
/// once right after `session.ready` and again on every change, a reader
/// attached or detached included (RAPP v26.10.29 §8.4 item 1, STPA CC-61
/// and CC-81).
@Suite
internal struct CardStatusReportsTests {
  /// Sessions of two computers the phone serves at once.
  private static let mac = "mac session"
  private static let laptop = "laptop session"

  /// The NFC card the holder added to the phone.
  private static let addedCard = RappCertificateFingerprint(
    certificate: Data("authentication certificate".utf8))

  @Test
  internal func everySessionHearsTheReaderAttachedAndDetached() throws {
    let card = RappCardPresence.present(try #require(Self.addedCard))
    let open = [Self.mac, Self.laptop]
    var reports = CardStatusReports<String>()

    let nearField = RappCardStatus(card: card, reader: .absent)
    #expect(reports.sessions(toTell: nearField, among: open) == open)

    let attached = RappCardStatus(card: card, reader: .attached)
    #expect(reports.sessions(toTell: attached, among: open) == open)
    #expect(reports.sessions(toTell: attached, among: open).isEmpty, "no word twice in a row")

    let detached = RappCardStatus(card: card, reader: .absent)
    #expect(reports.sessions(toTell: detached, among: open) == open)
  }

  @Test
  internal func aReaderDetachedWithItsCardIsOneWord() {
    let open = [Self.mac, Self.laptop]
    var reports = CardStatusReports<String>()
    _ = reports.sessions(toTell: RappCardStatus(card: .absent, reader: .attached), among: open)

    let gone = RappCardStatus(card: .absent, reader: .absent)
    #expect(reports.sessions(toTell: gone, among: open) == open)
    #expect(reports.sessions(toTell: gone, among: open).isEmpty)
  }

  @Test
  internal func aSessionHearsTheWordOnReadyWhateverItWasToldBefore() {
    var reports = CardStatusReports<String>()
    let word = RappCardStatus(card: .absent, reader: .attached)
    #expect(reports.sessions(toTell: word, among: [Self.mac]) == [Self.mac])

    #expect(
      reports.sessions(toTell: word, among: [Self.mac, Self.laptop]) == [Self.laptop],
      "a session established later hears the word once")

    reports.forget(Self.mac)
    #expect(
      reports.sessions(toTell: word, among: [Self.mac, Self.laptop]) == [Self.mac],
      "a new session.ready on the same session hears it again")
  }
}
