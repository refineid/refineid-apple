// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// The retry counters of an organization card on the contactless
/// interface: refused to every status form before PACE, and read through
/// the state MSE:Set AT answers, which spends no try.
internal struct SealedCardCounterTests {
  /// A sealed card: `6985` to everything but EF.CardAccess and MSE:Set AT,
  /// which answers each password reference with its scripted state.
  private final class SealedCard: CardChannel {
    private static let instructionOffset = 1

    private let states: [UInt8: StatusWord]
    private let cardAccessSelect = CommandApdu.selectElementaryFile(.cardAccess).encoded
    private let cardAccess = CardAccessFixture.organizationCard
    private let suite: PaceInfo?

    /// The instruction byte of every command received.
    private(set) var instructions: [UInt8] = []

    /// How many times EF.CardAccess was selected.
    private(set) var cardAccessSelects = 0

    var readChunkLength: ReadChunkLength { .plain }

    init(pin1: StatusWord, pin2: StatusWord, puk: StatusWord) {
      states = [
        FineidValues.organizationReference(for: .pin1): pin1,
        FineidValues.organizationReference(for: .pin2): pin2,
        FineidValues.organizationReference(for: .puk): puk,
      ]
      suite = (try? CardAccess.parse(cardAccess))?.genericMappingSuite
    }

    private static func octets(_ statusWord: StatusWord) -> Data {
      withUnsafeBytes(of: statusWord.encoded.bigEndian) { Data($0) }
    }

    func transmit(_ payload: Data) -> Data {
      let instruction = payload[payload.startIndex + Self.instructionOffset]
      instructions.append(instruction)
      switch instruction {
      case Iso7816Values.insManageSecurityEnvironment:
        return Self.octets(state(named: payload))

      case Iso7816Values.insSelect where payload == cardAccessSelect:
        cardAccessSelects += 1
        return Self.octets(.success)

      case Iso7816Values.insReadBinary:
        return cardAccess + Self.octets(.success)

      default:
        return Self.octets(.conditionsNotSatisfied)
      }
    }

    /// The state of the password `command` names.
    private func state(named command: Data) -> StatusWord {
      guard let suite else { return .referenceDataNotFound }
      let named = states.first { reference, _ in
        PaceCommand.securityEnvironment(suite: suite, passwordReference: reference) == command
      }
      return named?.value ?? .referenceDataNotFound
    }
  }

  /// Answers every command with success and records it.
  private final class RecordingChannel: CardChannel {
    private(set) var commands: [Data] = []

    var readChunkLength: ReadChunkLength { .plain }

    func transmit(_ payload: Data) -> Data {
      commands.append(payload)
      return withUnsafeBytes(of: StatusWord.success.encoded.bigEndian) { Data($0) }
    }
  }

  private static let fullAnswer = StatusWord.success
  private static let newPin = "975318"
  private static let lastTry: UInt8 = 1
  private static let noTries: UInt8 = 0
  private static let oneBelowFull = RetryCount.pristineAllowance - lastTry

  private static func count(_ attempts: UInt8) throws -> RetryCount {
    try #require(RetryCount(attemptsRemaining: attempts))
  }

  private static func left(_ attempts: UInt8) throws -> StatusWord {
    .pinIncorrect(remaining: try count(attempts))
  }

  @Test
  internal func aFullCardReadsItsThreeCountersAndNoTryIsSpent() throws {
    let card = SealedCard(pin1: Self.fullAnswer, pin2: Self.fullAnswer, puk: Self.fullAnswer)
    let report = try CardOperations(channel: card).probeCredentials()
    let full = try Self.count(RetryCount.pristineAllowance)
    #expect(report.pin1 == .remaining(full))
    #expect(report.pin2 == .remaining(full))
    #expect(report.puk == .remaining(full))
    #expect(!card.instructions.contains(PaceValues.insGeneralAuthenticate))
    #expect(card.cardAccessSelects == 1)
  }

  @Test
  internal func eachCounterReadsItsOwnPassword() throws {
    let lowPin = Self.oneBelowFull
    let lowPuk = RetryFloor.minimumAttemptsToProceed
    let card = SealedCard(
      pin1: try Self.left(lowPin),
      pin2: Self.fullAnswer,
      puk: try Self.left(lowPuk))
    let report = try CardOperations(channel: card).probeCredentials()
    #expect(report.pin1 == .remaining(try Self.count(lowPin)))
    #expect(report.pin2 == .remaining(try Self.count(RetryCount.pristineAllowance)))
    #expect(report.puk == .remaining(try Self.count(lowPuk)))
  }

  @Test
  internal func theOneFloorDecidesOnEachCredentialsReading() throws {
    let cases: [(StatusWord, RetryFloorVerdict)] = [
      (Self.fullAnswer, .proceed),
      (try Self.left(RetryFloor.minimumAttemptsToProceed), .proceed),
      (try Self.left(RetryFloor.minimumAttemptsToProceed - Self.lastTry), .refuseLowAttempts),
      (try Self.left(Self.lastTry), .refuseLowAttempts),
      (try Self.left(Self.noTries), .proceed),
      (.authenticationBlocked, .proceed),
    ]
    for (answer, verdict) in cases {
      let card = SealedCard(pin1: answer, pin2: answer, puk: answer)
      let report = try CardOperations(channel: card).probeCredentials()
      #expect(RetryFloor.evaluate(probeOutcome: report.pin1, presenting: .pin1) == verdict)
      #expect(RetryFloor.evaluate(probeOutcome: report.pin2, presenting: .pin2) == verdict)
      #expect(RetryFloor.evaluate(probeOutcome: report.puk, presenting: .puk) == verdict)
    }
  }

  @Test
  internal func aPasswordThatReportsNoStateStaysUnreadable() throws {
    let refused = StatusWord.referenceDataNotFound
    let card = SealedCard(pin1: refused, pin2: refused, puk: refused)
    let report = try CardOperations(channel: card).probeCredentials()
    let unreadable = RetryProbeOutcome.other(StatusWord.conditionsNotSatisfied.encoded)
    #expect(report.pin1 == unreadable)
    #expect(RetryFloor.evaluate(probeOutcome: report.pin1, presenting: .pin1) == .refuseUnreadable)
    #expect(RetryFloor.evaluate(probeOutcome: report.puk, presenting: .puk) == .refuseUnreadable)
  }

  @Test
  internal func aDeactivatedPasswordReadsInvalidated() {
    let answer = RetryProbeOutcome(
      passwordStateAnswer: .other(PaceValues.swPasswordDeactivated))
    #expect(answer == .invalidated)
  }

  @Test
  internal func aSealedCardIsOnTheOrganizationNumbering() throws {
    let card = SealedCard(pin1: Self.fullAnswer, pin2: Self.fullAnswer, puk: Self.fullAnswer)
    let lengths = try CardOperations(channel: card).readCardPinLengths()
    #expect(lengths.numbering == .organization)
  }

  @Test
  internal func aPukOnItsOwnChannelIsNotSentAgainForAReset() throws {
    let channel = RecordingChannel()
    let operations = CardOperations(channel: channel, openedWith: .puk)
    guard let wire = Pin1(digits: Self.newPin), let sent = Pin1(digits: Self.newPin) else {
      Issue.record("valid PIN failed to construct")
      return
    }
    let expected = CredentialBearingCommand.resetPin1AfterVerifiedUnblock(
      new: wire.consumeForSingleTransmission(),
      references: .organization
    )
    .intoTransportPayload()
    try operations.resetPin1OnPukChannel(
      new: sent.consumeForSingleTransmission(),
      lengths: .notListed(numbering: .organization))
    #expect(channel.commands == [expected])
  }

  @Test
  internal func aPin2ResetOnThePukChannelRunsFromItsDirectory() throws {
    let channel = RecordingChannel()
    let operations = CardOperations(channel: channel, openedWith: .puk)
    guard let wire = Pin2(digits: Self.newPin), let sent = Pin2(digits: Self.newPin) else {
      Issue.record("valid PIN failed to construct")
      return
    }
    let expected = CredentialBearingCommand.resetPin2AfterVerifiedUnblock(
      new: wire.consumeForSingleTransmission(),
      references: .organization
    )
    .intoTransportPayload()
    try operations.resetPin2OnPukChannel(
      new: sent.consumeForSingleTransmission(),
      lengths: .notListed(numbering: .organization))
    #expect(
      channel.commands == [
        CommandApdu.selectFile(.mainFile, selectionP1: Iso7816Values.selectByFileIdP1).encoded,
        CommandApdu.selectApplication(.esignDirectory).encoded,
        expected,
      ])
  }

  @Test
  internal func theCountersAfterAChannelAreReadOverThePlainTransportFromTheMainFile() throws {
    let plain = SealedCard(pin1: Self.fullAnswer, pin2: Self.fullAnswer, puk: Self.fullAnswer)
    let secure = RecordingChannel()
    let operations = CardOperations(channel: secure, openedWith: .puk, plainChannel: plain)
    let report = try operations.credentialsAfterChannel()
    #expect(report.puk == .remaining(try Self.count(RetryCount.pristineAllowance)))
    #expect(
      secure.commands == [
        CommandApdu.selectFile(.mainFile, selectionP1: Iso7816Values.selectByFileIdP1).encoded
      ])
  }
}
