// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import RappEngine
import Testing

@testable import RefineIDTestHost

/// The line right after this Mac's user paired a phone (RAPP v26.11.8 §4.7).
@Suite
internal struct IdentityLineJustPairedTests {
  private static let phone = "Alpha iPhone"

  /// Remote use on, nothing here, a phone just paired.
  private static let justPaired = RequesterFacts(
    availability: .noCard,
    warnsUnavailableCard: false,
    readerConnected: false,
    cardPresent: false,
    remoteUse: true,
    phonePaired: true,
    phoneJustPaired: phone
  )

  /// The phone's word: a card in its reader.
  private static let cardInReader = RappCertificateFingerprint(
    certificate: Data("authentication certificate".utf8)
  ).map { RappCardStatus(card: .present($0), reader: .attached) }

  @Test("A phone just paired is being connected to, in place of the code entry")
  internal func connectingInPlaceOfTheCodeEntry() {
    #expect(IdentityLine.derive(Self.justPaired) == .connectingToPairedPhone(Self.phone))
  }

  @Test("A phone just paired that offers its card shows the holder")
  internal func cardStatusEndsTheConnecting() {
    var facts = Self.justPaired
    facts.availability = .ready
    facts.phoneCardStatus = Self.cardInReader
    #expect(IdentityLine.derive(facts) == .paired(.holder))
  }

  @Test("A local card overrides a phone just paired")
  internal func localCardOverrides() {
    var facts = Self.justPaired
    facts.availability = .ready
    facts.cardPresent = true
    #expect(IdentityLine.derive(facts) == .localHolder)
  }

  @Test("Without a pairing the code entry stands")
  internal func noPairingAsksForACode() {
    var facts = Self.justPaired
    facts.phonePaired = false
    #expect(IdentityLine.derive(facts) == .pairPhone)
  }
}
