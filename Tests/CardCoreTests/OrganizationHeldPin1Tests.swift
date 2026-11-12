// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// A held PIN 1 on an organization card's antenna: the card takes a try at
/// the first GENERAL AUTHENTICATE of PACE, so a held value is sent only
/// while MSE:Set AT shows no refusal since the card accepted it, and a
/// value the card refuses is dropped at once.
@Suite
internal struct OrganizationHeldPin1Tests {
  /// Thrown when a fixture PIN does not construct.
  private struct InvalidFixturePin: Error {}

  /// The PIN 1 the card now expects, fictitious.
  private static let cardPinDigits = "2468"

  /// The PIN 1 held from before it was changed elsewhere, fictitious.
  private static let heldPinDigits = "1357"

  private static let serialValue = "ORGTEST0001"

  /// The MSE:Set AT password reference of PIN 1 (FINEID S4-2 v4.0
  /// section 6).
  private static let pin1Reference: UInt8 = 0x03

  /// NIST P-384 (BSI TR-03110-3 table 4).
  private static let nistP384Parameter: UInt8 = 15

  /// A PIN state with four tries left.
  private static let fourTriesLeftHex = "63C4"

  /// The PIN blocked by the refusal.
  private static let blockedHex = "6983"

  /// MSE:Set AT reports the PIN password deactivated (BSI TR-03110-3
  /// section B.14.1).
  private static let passwordDeactivatedHex = "6283"

  /// Two AES blocks of nonce, as the organization card sends it.
  private static let nonceHex =
    "000102030405060708090A0B0C0D0E0F" + "F0E1D2C3B4A5968778695A4B3C2D1E0F"

  /// Sixteen-byte building blocks for the card's fixed scalars.
  private static let firstBlockHex = "0F1E2D3C4B5A69788796A5B4C3D2E1F0"
  private static let secondBlockHex = "1A2B3C4D5E6F708192A3B4C5D6E7F809"
  private static let thirdBlockHex = "2C3D4E5F60718293A4B5C6D7E8F90A1B"
  private static let fourthBlockHex = "3D4E5F60718293A4B5C6D7E8F90A1B2C"

  private static func scalar(_ hex: String) throws -> U384 {
    try #require(U384(bigEndianBytes: WireHex.data(hex)))
  }

  /// An organization card over P-384 expecting ``cardPinDigits``.
  private static func card(
    templateStatus: String = SyntheticPaceCardValues.successHex,
    refusedTokenStatus: String = SyntheticPaceCardValues.authenticationFailedHex
  ) throws -> SyntheticPaceCard<NistP384> {
    var configuration = SyntheticPaceCard<NistP384>.Configuration(
      passwordDigits: cardPinDigits,
      passwordReference: pin1Reference,
      domainParameter: nistP384Parameter,
      nonce: WireHex.data(nonceHex),
      mappingScalar: try scalar(thirdBlockHex + fourthBlockHex + firstBlockHex),
      agreementScalar: try scalar(fourthBlockHex + firstBlockHex + secondBlockHex),
      cardAccess: CardAccessFixture.organizationCard
    )
    configuration.authenticationTemplateStatusHex = templateStatus
    configuration.refusedTokenStatusHex = refusedTokenStatus
    return SyntheticPaceCard(configuration)
  }

  private static func serial() throws -> ChipSerial {
    try #require(ChipSerial(value: serialValue))
  }

  /// A memory holding `digits` as accepted by the card.
  private static func memory(holding digits: String, serial: ChipSerial) throws -> Pin1Memory {
    let memory = Pin1Memory()
    guard let pin = Pin1(digits: digits) else { throw InvalidFixturePin() }
    memory.commit(
      memory.acceptance(of: pin, serial: serial, owner: Pin1Memory.Owner()), after: .verified)
    return memory
  }

  /// One signature's opening with the held PIN.
  private static func openHeld(
    _ card: SyntheticPaceCard<NistP384>,
    memory: Pin1Memory,
    rejected: RejectedPinMemory,
    serial: ChipSerial
  ) throws {
    _ = try OrganizationCardOpening.pin1(
      over: card,
      entered: nil,
      serial: serial,
      records: OrganizationCardOpening.Pin1Records(
        memory: memory, rejected: rejected, owner: Pin1Memory.Owner())
    )
  }

  private static func holds(_ memory: Pin1Memory, _ serial: ChipSerial) -> Bool {
    guard let held = memory.checkoutAccepted(serial: serial) else { return false }
    _ = held
    return true
  }

  @Test(arguments: [
    fourTriesLeftHex, blockedHex, SyntheticPaceCardValues.authenticationFailedHex,
  ])
  internal func aHeldPinTheCardRefusesIsDroppedAndTheNextSignaturePrompts(
    refusal: String
  ) throws {
    let serial = try Self.serial()
    let memory = try Self.memory(holding: Self.heldPinDigits, serial: serial)
    let rejected = RejectedPinMemory()
    let card = try Self.card(refusedTokenStatus: refusal)

    #expect(throws: PaceEstablishment.Failure.self) {
      try Self.openHeld(card, memory: memory, rejected: rejected, serial: serial)
    }
    #expect(!Self.holds(memory, serial))

    let sent = card.instructions.count
    #expect(throws: OrganizationCardOpening.Pin1Unsettled.entryRequired) {
      try Self.openHeld(card, memory: memory, rejected: rejected, serial: serial)
    }
    #expect(card.instructions.count == sent)
  }

  @Test
  internal func aHeldPinIsNotSentWhenTheCardReportsARefusalSinceItWasAccepted() throws {
    let serial = try Self.serial()
    let memory = try Self.memory(holding: Self.cardPinDigits, serial: serial)
    let card = try Self.card(templateStatus: Self.fourTriesLeftHex)

    #expect(throws: OrganizationCardOpening.Pin1Unsettled.entryRequired) {
      try Self.openHeld(card, memory: memory, rejected: RejectedPinMemory(), serial: serial)
    }
    #expect(card.generalAuthenticateCount == 0)
    #expect(card.sessionKeys == nil)
    #expect(!Self.holds(memory, serial))
  }

  @Test
  internal func aHeldPinAtTheFullAllowanceCompletesTheHandshake() throws {
    let serial = try Self.serial()
    let memory = try Self.memory(holding: Self.cardPinDigits, serial: serial)
    let card = try Self.card()

    // The application select after the handshake is outside this card's
    // script; the handshake itself completed with the held PIN.
    _ = try? Self.openHeld(card, memory: memory, rejected: RejectedPinMemory(), serial: serial)
    #expect(card.sessionKeys != nil)
    #expect(Self.holds(memory, serial))
  }

  @Test
  internal func aTypedPinIsSentAtFourTriesLeft() throws {
    let serial = try Self.serial()
    let card = try Self.card(templateStatus: Self.fourTriesLeftHex)
    guard let typed = Pin1(digits: Self.cardPinDigits) else { throw InvalidFixturePin() }

    _ = try? OrganizationCardOpening.pin1(
      over: card,
      entered: typed,
      serial: serial,
      records: OrganizationCardOpening.Pin1Records(
        memory: Pin1Memory(), rejected: RejectedPinMemory(), owner: Pin1Memory.Owner())
    )
    #expect(card.sessionKeys != nil)
  }

  @Test
  internal func aThrowingOrRejectedTemplateProbeDropsTheHeldPin() throws {
    struct DisconnectedChannel: CardChannel {
      var readChunkLength: ReadChunkLength { .plain }

      func transmit(_: Data) throws -> Data {
        throw CardOperationError.exchangeUnanswered
      }
    }

    let serial = try Self.serial()
    let memory = try Self.memory(holding: Self.cardPinDigits, serial: serial)

    #expect(throws: CardOperationError.exchangeUnanswered) {
      _ = try OrganizationCardOpening.pin1(
        over: DisconnectedChannel(),
        entered: nil,
        serial: serial,
        records: OrganizationCardOpening.Pin1Records(
          memory: memory, rejected: RejectedPinMemory(), owner: Pin1Memory.Owner())
      )
    }
    #expect(!Self.holds(memory, serial))

    let deactivatedMemory = try Self.memory(holding: Self.cardPinDigits, serial: serial)
    let deactivatedCard = try Self.card(templateStatus: Self.passwordDeactivatedHex)
    #expect(throws: PaceEstablishment.Failure.passwordDeactivated) {
      try Self.openHeld(
        deactivatedCard, memory: deactivatedMemory, rejected: RejectedPinMemory(), serial: serial)
    }
    #expect(!Self.holds(deactivatedMemory, serial))
  }
}
