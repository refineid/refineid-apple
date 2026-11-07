// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore
  @testable import RefineIDTestHost

  /// Opening a card for an operation that spends a PIN, decided by the
  /// card's own answers and not by its answer to reset, which the phone's
  /// antenna reports without the prefix a reader synthesizes for a
  /// contactless card.
  internal struct CardMaintenanceOpeningTests {
    /// A card that answers the application select with `application`, and
    /// before PACE refuses every other select with `6985`, except
    /// EF.CardAccess, which it reports missing so the handshake stops
    /// after asking for it.
    private final class ScriptedCard: CardChannel {
      /// Where a command's instruction byte sits: after its class byte
      /// (ISO/IEC 7816-4 section 5.1).
      private static let instructionOffset = 1

      private let application: StatusWord
      private let applicationSelect = CommandApdu.selectApplication(.fineidApplication).encoded
      private let cardAccessSelect = CommandApdu.selectElementaryFile(.cardAccess).encoded

      /// Every command received, in order.
      private(set) var commands: [Data] = []

      var readChunkLength: ReadChunkLength { .plain }

      /// Whether EF.CardAccess was asked for, which PACE does first.
      var startedPace: Bool {
        commands.contains(cardAccessSelect)
      }

      init(application: StatusWord) {
        self.application = application
      }

      /// The two octets of `statusWord`.
      private static func octets(_ statusWord: StatusWord) -> Data {
        withUnsafeBytes(of: statusWord.encoded.bigEndian) { Data($0) }
      }

      func transmit(_ payload: Data) -> Data {
        commands.append(payload)
        if payload == applicationSelect {
          return Self.octets(application)
        }
        if payload == cardAccessSelect {
          return Self.octets(.fileNotFound)
        }
        return Self.octets(.conditionsNotSatisfied)
      }

      /// Whether a command with `instruction` was received.
      func received(instruction: UInt8) -> Bool {
        commands.contains { command in
          command.count > Self.instructionOffset
            && command[command.startIndex + Self.instructionOffset] == instruction
        }
      }
    }

    /// A fictitious PIN 2.
    private static let pin2Digits = "2468"
    private static let pukDigits = "13579246"

    @Test
    internal func anOrganizationCardWhoseSelectSucceedsGoesToPaceWithItsPin() {
      let card = ScriptedCard(application: .success)
      let opener = CardMaintenance.CardOpener<CardMaintenance.Outcome>.pin(
        .pin2(Self.pin2Digits), cardAccessNumber: nil
      ) { outcome, _ in outcome }
      let opening = CardMaintenance.openedOperations(over: card, opener: opener)
      #expect(card.startedPace)
      #expect(!card.received(instruction: Iso7816Values.insVerify))
      if case .opened = opening {
        Issue.record("A card refusing its reads before PACE was opened in the clear")
      }
    }

    @Test
    internal func anOrganizationCardGoesToPaceWithThePukAResetPresents() {
      let card = ScriptedCard(application: .success)
      let opener = CardMaintenance.CardOpener<CardMaintenance.Outcome>.pin(
        .puk(Self.pukDigits), cardAccessNumber: nil
      ) { outcome, _ in outcome }
      let opening = CardMaintenance.openedOperations(over: card, opener: opener)
      #expect(card.startedPace)
      #expect(!card.received(instruction: Iso7816Values.insVerify))
      #expect(!card.received(instruction: Iso7816Values.insResetRetryCounter))
      if case .opened = opening {
        Issue.record("A card refusing its reads before PACE was opened in the clear")
      }
    }

    @Test
    internal func aPersonalCardIsSentNoVerifyForAnOperationsPin() {
      let card = ScriptedCard(application: .securityNotSatisfied)
      let opener = CardMaintenance.CardOpener<CardMaintenance.Outcome>.pin(
        .pin2(Self.pin2Digits), cardAccessNumber: nil
      ) { outcome, _ in outcome }
      _ = CardMaintenance.openedOperations(over: card, opener: opener)
      #expect(!card.received(instruction: Iso7816Values.insVerify))
    }
  }

#endif
