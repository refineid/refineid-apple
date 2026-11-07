// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore
  @testable import RefineIDTestHost

  /// The floor before a PIN change or reset, judged on the credential the
  /// command presents: a credential at no tries left or blocked is passed
  /// to the card, which answers for itself.
  internal struct CardMaintenanceFloorTests {
    private struct UnexpectedCommand: Error {}

    /// A card that answers each expected command in turn and nothing
    /// else: the script is the whole exchange, so an exhausted script
    /// proves every command in it reached the card.
    private final class ScriptedCard: CardChannel {
      private var script: [(request: Data, response: Data)]

      var readChunkLength: ReadChunkLength { .plain }

      var isExhausted: Bool { script.isEmpty }

      init(_ script: [(request: Data, response: Data)]) {
        self.script = script
      }

      func transmit(_ payload: Data) throws -> Data {
        guard let next = script.first, next.request == payload else {
          Issue.record("unexpected command of \(payload.count) bytes")
          throw UnexpectedCommand()
        }
        script.removeFirst()
        return next.response
      }
    }

    /// The authentication-method byte of a PIN-container attributes
    /// object as a citizen card reports it (S1 v4.2 §3.15.3 Table 19);
    /// the counter parser does not read it.
    private static let authenticationMethod: UInt8 = 0xFF

    /// A fictitious PUK, preset activation PIN and PIN 1 of the lengths
    /// a citizen card accepts.
    private static let pukDigits = "12345678"
    private static let activationPinDigits = "1234567"
    private static let pin1Digits = "4321"

    /// `statusWord` after `body`, as the card puts it on the wire.
    private static func answer(_ statusWord: StatusWord, body: Data = Data()) -> Data {
      body + withUnsafeBytes(of: statusWord.encoded.bigEndian) { Data($0) }
    }

    /// A PIN-container answer whose attributes object carries `tries`.
    private static func attributes(tries: UInt8) -> Data {
      Data([
        FineidValues.pinAttributesTagHigh,
        FineidValues.pinAttributesTagLow,
        FineidValues.pinAttributesLength,
        tries,
        FineidValues.usageUnlimited,
        FineidValues.unblockingUnlimited,
        Self.authenticationMethod,
      ])
    }

    private static func unblockPin1(
      on operations: CardOperations,
      lengths: CardPinLengths
    ) -> CardMaintenance.Outcome {
      guard let puk = Puk(digits: Self.pukDigits), let pin = Pin1(digits: Self.pin1Digits) else {
        Issue.record("valid credential failed to construct")
        return .failed
      }
      do {
        try operations.unblockPin1(
          puk: puk.consumeForSingleTransmission(),
          new: pin.consumeForSingleTransmission(),
          lengths: lengths
        )
        return .success
      } catch {
        return CardMaintenance.outcome(of: error)
      }
    }

    /// The citizen card's one-command unblock on the wire.
    private static func citizenUnblockPin1Command() -> Data {
      guard let puk = Puk(digits: Self.pukDigits), let pin = Pin1(digits: Self.pin1Digits) else {
        Issue.record("valid credential failed to construct")
        return Data()
      }
      return CredentialBearingCommand.unblockPin1(
        puk: puk.consumeForSingleTransmission(),
        new: pin.consumeForSingleTransmission(),
        references: .citizen
      )
      .intoTransportPayload()
    }

    /// The organization card's PUK verify on the wire, which precedes
    /// its reset and carries the PUK.
    private static func organizationVerifyPukCommand() -> Data {
      guard let puk = Puk(digits: Self.pukDigits) else {
        Issue.record("valid credential failed to construct")
        return Data()
      }
      return CredentialBearingCommand.verifyUnblockCredential(
        puk.consumeForSingleTransmission(),
        references: .organization
      )
      .intoTransportPayload()
    }

    /// The preset activation PIN presented as the current PIN 1 on the
    /// wire.
    private static func presetPin1ChangeCommand() -> Data {
      guard
        let preset = Pin1(digits: Self.activationPinDigits),
        let pin = Pin1(digits: Self.pin1Digits)
      else {
        Issue.record("valid credential failed to construct")
        return Data()
      }
      return CredentialBearingCommand.changePin1(
        current: preset.consumeForSingleTransmission(),
        new: pin.consumeForSingleTransmission(),
        references: .citizen
      )
      .intoTransportPayload()
    }

    @Test
    internal func aPukAtNoTriesLeftIsPassedToTheCitizenCard() throws {
      let none = try #require(RetryCount(attemptsRemaining: 0))
      let lengths = CardPinLengths.notListed(numbering: .citizen)
      // The PIN-container probe reads the PUK at no tries left; the reset
      // still goes out, and the card answers blocked.
      let card = ScriptedCard([
        (
          CommandApdu.readCredentialAttributes(role: .puk).encoded,
          Self.answer(.success, body: Self.attributes(tries: none.attemptsRemaining))
        ),
        (Self.citizenUnblockPin1Command(), Self.answer(.authenticationBlocked)),
      ])
      let operations = CardOperations(channel: card)

      let outcome = CardMaintenance.floored(presenting: .puk, on: operations, lengths: lengths) {
        operations, lengths in
        Self.unblockPin1(on: operations, lengths: lengths)
      }

      #expect(outcome == .pinBlocked)
      #expect(card.isExhausted)
    }

    @Test
    internal func aBlockedPukIsPassedToTheOrganizationCard() {
      let lengths = CardPinLengths.notListed(numbering: .organization)
      // The organization card has no PIN container; its PUK answers the
      // VERIFY status probe as blocked, and the PUK verify still goes out.
      let card = ScriptedCard([
        (
          CommandApdu.readCredentialAttributes(role: .puk).encoded,
          Self.answer(.referenceDataNotFound)
        ),
        (
          CommandApdu.readRetryCounter(role: .puk, references: .organization).encoded,
          Self.answer(.authenticationBlocked)
        ),
        (Self.organizationVerifyPukCommand(), Self.answer(.authenticationBlocked)),
      ])
      let operations = CardOperations(channel: card)

      let outcome = CardMaintenance.floored(presenting: .puk, on: operations, lengths: lengths) {
        operations, lengths in
        Self.unblockPin1(on: operations, lengths: lengths)
      }

      #expect(outcome == .pinBlocked)
      #expect(card.isExhausted)
    }

    @Test
    internal func aPresetActivationPinAtNoTriesLeftIsPassedToTheCard() {
      // PIN 1 probes blocked; the activation change still goes out, and
      // the card answers blocked.
      let card = ScriptedCard([
        (
          CommandApdu.readRetryCounter(role: .pin1, references: .citizen).encoded,
          Self.answer(.authenticationBlocked)
        ),
        (Self.presetPin1ChangeCommand(), Self.answer(.authenticationBlocked)),
      ])
      let request = CardMaintenance.ActivationRequest(
        entry: Self.activationPinDigits,
        newPin1: Self.pin1Digits,
        newPin2: nil,
        scheme: .presetActivationPin,
        needs: CardActivationNeeds(pin1: true, pin2: false)
      )

      let report = CardMaintenance.runActivation(
        CardOperations(channel: card),
        request: request,
        lengths: .notListed(numbering: .citizen)
      )

      #expect(report?.pin1 == .pinBlocked)
      #expect(report?.pin2 == nil)
      #expect(card.isExhausted)
    }

    @Test
    internal func aPresetActivationPinAtTwoTriesLeftIsRefusedBeforeTheCard() throws {
      let two = try #require(RetryCount(attemptsRemaining: RetryCount.lowAttemptCeiling))
      let card = ScriptedCard([
        (
          CommandApdu.readRetryCounter(role: .pin1, references: .citizen).encoded,
          Self.answer(.pinIncorrect(remaining: two))
        )
      ])
      let request = CardMaintenance.ActivationRequest(
        entry: Self.activationPinDigits,
        newPin1: Self.pin1Digits,
        newPin2: nil,
        scheme: .presetActivationPin,
        needs: CardActivationNeeds(pin1: true, pin2: false)
      )

      let report = CardMaintenance.runActivation(
        CardOperations(channel: card),
        request: request,
        lengths: .notListed(numbering: .citizen)
      )

      #expect(report?.pin1 == .floorRefused(.refuseLowAttempts))
      #expect(card.isExhausted)
    }

    @Test
    internal func aPukAtTwoTriesLeftIsRefusedBeforeTheCard() throws {
      let two = try #require(RetryCount(attemptsRemaining: RetryCount.lowAttemptCeiling))
      let lengths = CardPinLengths.notListed(numbering: .citizen)
      let card = ScriptedCard([
        (
          CommandApdu.readCredentialAttributes(role: .puk).encoded,
          Self.answer(.success, body: Self.attributes(tries: two.attemptsRemaining))
        )
      ])
      let operations = CardOperations(channel: card)

      let outcome = CardMaintenance.floored(presenting: .puk, on: operations, lengths: lengths) {
        operations, lengths in
        Self.unblockPin1(on: operations, lengths: lengths)
      }

      #expect(outcome == .floorRefused(.refuseLowAttempts))
      #expect(card.isExhausted)
    }

    @Test
    internal func aBlockedPin1GoesToTheCard() {
      let lengths = CardPinLengths.notListed(numbering: .citizen)
      let card = ScriptedCard([
        (
          CommandApdu.readRetryCounter(role: .pin1, references: .citizen).encoded,
          Self.answer(.authenticationBlocked)
        )
      ])
      let operations = CardOperations(channel: card)

      var reached = false
      let outcome = CardMaintenance.floored(presenting: .pin1, on: operations, lengths: lengths) {
        _, _ in
        reached = true
        return .pinBlocked
      }

      #expect(reached)
      #expect(outcome == .pinBlocked)
      #expect(card.isExhausted)
    }
  }

#endif
