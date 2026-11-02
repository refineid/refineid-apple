// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// The phone's opening of a card on its antenna: the card's kind from its
/// first answer, an organization card opened with PIN 1 or PIN 2, and a
/// personal card left to its card access number.
internal struct OrganizationCardOpeningTests {
  /// Thrown when a fixture PIN does not construct.
  private struct InvalidFixturePin: Error {}

  /// The answer to the application select inside the channel.
  private static let selected: (payload: Data, statusWord: Data) = (
    Data(), SyntheticAntennaCard<NistP384>.octets(.success)
  )

  private static func card(
    pin role: CredentialRole,
    refusal: StatusWord = .conditionsNotSatisfied,
    afterPace: [(payload: Data, statusWord: Data)] = []
  ) throws -> SyntheticAntennaCard<NistP384> {
    SyntheticAntennaCard(
      pace: try PaceEstablishmentTests.organizationCardConfiguration(pin: role),
      refusal: refusal,
      afterPace: afterPace)
  }

  private static func pin1() throws -> Pin1Transmission {
    guard let pin = Pin1(digits: PaceEstablishmentTests.organizationPinDigits) else {
      throw InvalidFixturePin()
    }
    return pin.consumeForSingleTransmission()
  }

  private static func pin2() throws -> Pin2Transmission {
    guard let pin = Pin2(digits: PaceEstablishmentTests.organizationPinDigits) else {
      throw InvalidFixturePin()
    }
    return pin.consumeForSingleTransmission()
  }

  /// Whether `card` was sent MANAGE SECURITY ENVIRONMENT, which carries
  /// the password reference.
  private static func sentSecurityEnvironment(_ card: SyntheticAntennaCard<NistP384>) -> Bool {
    card.plainCommands.contains { command in
      command.count > SyntheticPaceCardValues.instructionOffset
        && command[command.startIndex + SyntheticPaceCardValues.instructionOffset]
          == SyntheticPaceCardValues.manageSecurityEnvironment
    }
  }

  @Test
  internal func anOrganizationCardIsToldByItsRefusalBeforePace() throws {
    let card = try Self.card(pin: .pin1)
    #expect(ContactlessCardKind.of(CardOperations(channel: card)) == .organization)
    #expect(!Self.sentSecurityEnvironment(card))
  }

  @Test
  internal func aPersonalCardKeepsTheCardAccessNumberPathAndIsSentNoPin() throws {
    let card = try Self.card(pin: .pin1, refusal: .securityNotSatisfied)
    #expect(ContactlessCardKind.of(CardOperations(channel: card)) == .personal)
    #expect(card.plainCommands.count == 1)
    #expect(!Self.sentSecurityEnvironment(card))
  }

  @Test
  internal func pin1OpensTheChannelAndSelectsTheApplicationInIt() throws {
    let card = try Self.card(pin: .pin1, afterPace: [Self.selected])
    let opened = try OrganizationCardOpening.pin1(over: card, try Self.pin1(), spending: .entered)
    #expect(opened.operations.channelPin == .pin1)
    let initial = try #require(RetryCount(attemptsRemaining: RetryCount.pristineAllowance))
    #expect(opened.pinState == .remaining(initial))
    #expect(card.secureCard?.receivedCommands.count == 1)
  }

  @Test
  internal func pin2OpensTheChannelAndLeavesTheCardAtTheMainFile() throws {
    let card = try Self.card(pin: .pin2)
    let opened = try OrganizationCardOpening.pin2(over: card, try Self.pin2())
    #expect(opened.operations.channelPin == .pin2)
    #expect(card.secureCard?.receivedCommands.isEmpty == true)
  }

  @Test
  internal func aHeldPin1IsNotSentToACardThatRefusedSinceItWasAccepted() throws {
    var configuration = try PaceEstablishmentTests.organizationCardConfiguration(pin: .pin1)
    configuration.authenticationTemplateStatusHex = PaceEstablishmentTests.fourTriesLeftStatusHex
    let card = SyntheticAntennaCard(
      pace: configuration, refusal: .conditionsNotSatisfied, afterPace: [])
    #expect(throws: PaceEstablishment.Failure.self) {
      try OrganizationCardOpening.pin1(over: card, try Self.pin1(), spending: .heldPin1)
    }
    #expect(
      !card.plainCommands.contains { command in
        command.count > SyntheticPaceCardValues.instructionOffset
          && command[command.startIndex + SyntheticPaceCardValues.instructionOffset]
            == SyntheticPaceCardValues.generalAuthenticate
      })
  }

  @Test
  internal func anOrganizationEntryIsNoCardAccessNumber() throws {
    // The organization entry is a Pin1Entry: it issues single-use PINs and
    // reflects as nothing, so no path can read its digits back into a
    // CardAccessNumber or a card access number store.
    let entry = try #require(Pin1Entry(digits: PaceEstablishmentTests.organizationPinDigits))
    #expect(Mirror(reflecting: entry).children.isEmpty)
    #expect(!((entry as Any) is CardAccessNumber))
    #expect(!((entry as Any) is CustomStringConvertible))
    // Four to twelve digits, which a personal card's six-digit number is
    // not: the two entries do not share a validation.
    #expect(CardAccessNumber(digits: PaceEstablishmentTests.organizationPinDigits) == nil)
  }
}
