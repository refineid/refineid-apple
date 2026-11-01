// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// The offline gate for PACE.
///
/// `SyntheticPaceCard` plays the card half of the protocol with its own
/// EF.CardAccess, its own nonce, its own two ephemeral scalars and its own
/// key derivation. Both sides therefore reach Kenc and Kmac by independent
/// routes, and if the two results agree the whole exchange agreed: the
/// suite choice, the nonce decryption, the generic mapping, the key
/// agreement on the mapped generator, and the two authentication token
/// encodings. Nothing here touches hardware, and the deterministic scalar
/// source is what makes the run reproducible.
@Suite
internal struct PaceEstablishmentTests {
  /// Thrown when a fixture PIN does not construct.
  private struct InvalidFixturePin: Error {}

  /// The citizen card access number these runs use.
  ///
  /// Fictitious, like every other secret in this file.
  private static let accessNumberDigits = "123456"

  /// A different, equally fictitious CAN, for the wrong-CAN run.
  private static let wrongAccessNumberDigits = "654321"

  /// A fictitious organization card PIN.
  private static let pinDigits = "2468"

  /// A different, equally fictitious PIN, for the wrong-PIN run.
  private static let wrongPinDigits = "1357"

  /// The MSE:Set AT password references (BSI TR-03110-3 section B.14.1;
  /// FINEID S4-2 v4.0 sections 4.2 and 6): CAN, PIN 1, PIN 2.
  private static let canReference: UInt8 = 0x02
  private static let pin1Reference: UInt8 = 0x03
  private static let pin2Reference: UInt8 = 0x04

  /// Standardized domain parameters (BSI TR-03110-3 table 4).
  private static let nistP256Parameter: UInt8 = 12
  private static let nistP384Parameter: UInt8 = 15
  private static let brainpoolP384Parameter: UInt8 = 16

  /// The answers MSE:Set AT gives for a PIN's state.
  private static let twoTriesLeftHex = "63C2"
  private static let oneTryLeftHex = "63C1"
  private static let blockedHex = "63C0"
  private static let threeTriesLeftHex = "63C3"
  private static let deactivatedHex = "6283"

  /// The answer to a wrong PIN at the last round: four tries left.
  private static let fourTriesLeftHex = "63C4"
  private static let triesLeftAfterWrongPin: UInt8 = 4

  /// The tries an untouched organization PIN has.
  private static let initialTries: UInt8 = 5

  /// The longest nonce the handshake accepts, in AES blocks.
  private static let longestNonceBlocks = 4

  /// The MANAGE SECURITY ENVIRONMENT instruction.
  private static let manageSecurityEnvironment: UInt8 = 0x22

  /// One AES block of nonce, as the citizen cards send it.
  private static let oneBlockNonceHex = "000102030405060708090A0B0C0D0E0F"

  /// Two AES blocks of nonce, as the organization card sends it.
  private static let twoBlockNonceHex = oneBlockNonceHex + "F0E1D2C3B4A5968778695A4B3C2D1E0F"

  /// An octet with every bit set, for nonces wider than the group order.
  private static let allOnesHex = "FF"

  /// Sixteen-byte building blocks for the fixed scalars.
  ///
  /// Each block's leading byte is well below `8C`, the leading byte of the
  /// brainpoolP384r1 order, so every scalar assembled from them lies in
  /// `[1, n)` of every curve here without a reduction.
  private static let firstBlockHex = "0F1E2D3C4B5A69788796A5B4C3D2E1F0"
  private static let secondBlockHex = "1A2B3C4D5E6F708192A3B4C5D6E7F809"
  private static let thirdBlockHex = "2C3D4E5F60718293A4B5C6D7E8F90A1B"
  private static let fourthBlockHex = "3D4E5F60718293A4B5C6D7E8F90A1B2C"

  /// A 384-bit or 256-bit scalar from its blocks.
  private static func scalar(_ blocks: [String], wide: Bool) throws -> U384 {
    let hex = wide ? blocks.joined() : blocks.prefix(2).joined()
    return try #require(U384(bigEndianBytes: WireHex.data(hex)))
  }

  /// The terminal's two fixed scalars, handed out in protocol order.
  private static func terminalScalars(wide: Bool) throws -> PaceEphemeralScalarSource {
    let scalars = [
      try Self.scalar([firstBlockHex, secondBlockHex, thirdBlockHex], wide: wide),
      try Self.scalar([secondBlockHex, thirdBlockHex, fourthBlockHex], wide: wide),
    ]
    var index = 0
    return PaceEphemeralScalarSource {
      let value = scalars[min(index, scalars.count - 1)]
      index += 1
      return value
    }
  }

  /// A synthetic card's configuration over `Curve`: the organization
  /// card's EF.CardAccess and two-block nonce unless a test says otherwise.
  private static func configuration<Curve: PaceCurve>(
    _: Curve.Type,
    password: String,
    reference: UInt8,
    domain: UInt8
  ) throws -> SyntheticPaceCard<Curve>.Configuration {
    let wide = Curve.coordinateByteCount == U384.byteCount
    return SyntheticPaceCard<Curve>.Configuration(
      passwordDigits: password,
      passwordReference: reference,
      domainParameter: domain,
      nonce: WireHex.data(Self.twoBlockNonceHex),
      mappingScalar: try Self.scalar([thirdBlockHex, fourthBlockHex, firstBlockHex], wide: wide),
      agreementScalar: try Self.scalar(
        [fourthBlockHex, firstBlockHex, secondBlockHex], wide: wide),
      cardAccess: CardAccessFixture.organizationCard
    )
  }

  /// The organization card's PIN 1 configuration over P-384.
  private static func organizationConfiguration() throws
    -> SyntheticPaceCard<NistP384>
    .Configuration
  {
    try Self.configuration(
      NistP384.self,
      password: Self.pinDigits,
      reference: Self.pin1Reference,
      domain: Self.nistP384Parameter
    )
  }

  /// A citizen card's configuration over brainpoolP384r1.
  private static func citizenConfiguration() throws
    -> SyntheticPaceCard<BrainpoolP384r1>
    .Configuration
  {
    var configuration = try Self.configuration(
      BrainpoolP384r1.self,
      password: Self.accessNumberDigits,
      reference: Self.canReference,
      domain: Self.brainpoolP384Parameter
    )
    configuration.nonce = WireHex.data(Self.oneBlockNonceHex)
    configuration.cardAccess = CardAccessFixture.citizenCard
    return configuration
  }

  /// A run over `card` with the fixed terminal scalars.
  private static func run<Curve: PaceCurve>(
    _ card: SyntheticPaceCard<Curve>,
    with password: consuming PacePassword
  ) throws -> PaceEstablishment.Established {
    let wide = Curve.coordinateByteCount == U384.byteCount
    return try PaceEstablishment(channel: card, scalarSource: try Self.terminalScalars(wide: wide))
      .establish(with: password)
  }

  private static func pin1(_ digits: String) throws -> PacePassword {
    guard let pin = Pin1(digits: digits) else { throw InvalidFixturePin() }
    return PacePassword(pin1: pin.consumeForSingleTransmission())
  }

  private static func pin2(_ digits: String) throws -> PacePassword {
    guard let pin = Pin2(digits: digits) else { throw InvalidFixturePin() }
    return PacePassword(pin2: pin.consumeForSingleTransmission())
  }

  private static func accessNumber(_ digits: String) throws -> PacePassword {
    PacePassword(cardAccessNumber: try #require(CardAccessNumber(digits: digits)))
  }

  /// An organization card over P-384 whose MSE:Set AT answers `status`.
  private static func organizationCard(status: String) throws -> SyntheticPaceCard<NistP384> {
    var configuration = try Self.organizationConfiguration()
    configuration.authenticationTemplateStatusHex = status
    return SyntheticPaceCard(configuration)
  }

  @Test
  internal func aCitizenCardRunsOverBrainpoolWithItsCardAccessNumber() throws {
    let card = SyntheticPaceCard(try Self.citizenConfiguration())
    let established = try Self.run(card, with: try Self.accessNumber(Self.accessNumberDigits))
    #expect(established.keys == (try #require(card.sessionKeys)))
    #expect(established.pinState == nil)
  }

  @Test
  internal func anOrganizationCardRunsOverP384WithPin1AndATwoBlockNonce() throws {
    let card = try Self.organizationCard(status: SyntheticPaceCardValues.successHex)
    let established = try Self.run(card, with: try Self.pin1(Self.pinDigits))
    #expect(established.keys == (try #require(card.sessionKeys)))
    let initial = try #require(RetryCount(attemptsRemaining: Self.initialTries))
    #expect(established.pinState == .remaining(initial))
  }

  @Test
  internal func pin2OnACardListingOnlyP256RunsOverP256() throws {
    // A nonce of every bit set is wider than the P-256 order, so the
    // terminal's reduction must agree with the card's unreduced Horner sum.
    var configuration = try Self.configuration(
      NistP256.self,
      password: Self.pinDigits,
      reference: Self.pin2Reference,
      domain: Self.nistP256Parameter
    )
    configuration.nonce = WireHex.data(
      String(repeating: Self.allOnesHex, count: NistP256.coordinateByteCount))
    configuration.cardAccess = CardAccessFixture.p256OnlyCard
    let card = SyntheticPaceCard(configuration)
    let established = try Self.run(card, with: try Self.pin2(Self.pinDigits))
    #expect(established.keys == (try #require(card.sessionKeys)))
  }

  @Test
  internal func theLongestNonceReducesAsTheCardMapsIt() throws {
    var configuration = try Self.organizationConfiguration()
    configuration.nonce = WireHex.data(
      String(repeating: Self.allOnesHex, count: AesCbc.blockSize * Self.longestNonceBlocks))
    let card = SyntheticPaceCard(configuration)
    let established = try Self.run(card, with: try Self.pin1(Self.pinDigits))
    #expect(established.keys == (try #require(card.sessionKeys)))
  }

  @Test
  internal func aNonceLongerThanFourBlocksIsRefusedBeforeTheNextCommand() throws {
    var configuration = try Self.organizationConfiguration()
    configuration.nonce = WireHex.data(
      String(repeating: Self.allOnesHex, count: AesCbc.blockSize * (Self.longestNonceBlocks + 1)))
    let card = SyntheticPaceCard(configuration)
    #expect(throws: PaceEstablishment.Failure.malformedResponse) {
      try Self.run(card, with: try Self.pin1(Self.pinDigits))
    }
    #expect(card.generalAuthenticateCount == 1)
  }

  @Test(arguments: [twoTriesLeftHex, oneTryLeftHex, blockedHex])
  internal func theFloorRefusesBeforeAnyGeneralAuthenticate(status: String) throws {
    let card = try Self.organizationCard(status: status)
    #expect {
      try Self.run(card, with: try Self.pin1(Self.pinDigits))
    } throws: { error in
      guard case PaceEstablishment.Failure.retryFloorRefused = error else { return false }
      return true
    }
    #expect(card.generalAuthenticateCount == 0)
    #expect(card.sessionKeys == nil)
  }

  @Test
  internal func theFloorServesThreeTriesLeft() throws {
    let card = try Self.organizationCard(status: Self.threeTriesLeftHex)
    let established = try Self.run(card, with: try Self.pin1(Self.pinDigits))
    #expect(established.keys == (try #require(card.sessionKeys)))
  }

  @Test
  internal func aDeactivatedPinSendsNothingFurther() throws {
    let card = try Self.organizationCard(status: Self.deactivatedHex)
    #expect(throws: PaceEstablishment.Failure.passwordDeactivated) {
      try Self.run(card, with: try Self.pin1(Self.pinDigits))
    }
    #expect(card.generalAuthenticateCount == 0)
  }

  @Test
  internal func aWrongPinReportsTheTriesLeft() throws {
    var configuration = try Self.organizationConfiguration()
    configuration.refusedTokenStatusHex = Self.fourTriesLeftHex
    let card = SyntheticPaceCard(configuration)
    let remaining = try #require(RetryCount(attemptsRemaining: Self.triesLeftAfterWrongPin))
    #expect(throws: PaceEstablishment.Failure.wrongPin(remaining: remaining)) {
      try Self.run(card, with: try Self.pin1(Self.wrongPinDigits))
    }
  }

  @Test
  internal func aWrongCardAccessNumberIsRefusedAtTheLastRound() throws {
    let card = SyntheticPaceCard(try Self.citizenConfiguration())
    // The card never signals the wrong CAN directly; a wrong password key
    // yields a wrong nonce, a different mapped generator, and therefore a
    // token the card refuses three rounds later.
    #expect(throws: PaceEstablishment.Failure.cardRejected(.authenticationFailed)) {
      try Self.run(card, with: try Self.accessNumber(Self.wrongAccessNumberDigits))
    }
  }

  @Test
  internal func aCardListingNoGenericSuiteIsNotSentTheSecurityEnvironment() throws {
    var configuration = try Self.organizationConfiguration()
    configuration.cardAccess = CardAccessFixture.integratedOnlyCard
    let card = SyntheticPaceCard(configuration)
    #expect(throws: PaceEstablishment.Failure.noSupportedSuite) {
      try Self.run(card, with: try Self.pin1(Self.pinDigits))
    }
    #expect(!card.instructions.contains(Self.manageSecurityEnvironment))
  }

  @Test
  internal func aCardAccessNumberIsExactlySixDigits() {
    #expect(CardAccessNumber(digits: "12345") == nil)
    #expect(CardAccessNumber(digits: "1234567") == nil)
    #expect(CardAccessNumber(digits: "12345A") == nil)
    #expect(CardAccessNumber(digits: "") == nil)
    #expect(CardAccessNumber(digits: Self.accessNumberDigits) != nil)
  }
}
