// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Dispatch
import Foundation

/// Card activation and PIN operations over an attached reader or NFC.
///
/// A mutation, its retry-floor probe, and its resulting state read share
/// one exclusive session. An NFC action therefore presents one system
/// sheet and never opens another sheet merely to refresh counters.
internal enum CardMaintenance {
  #if REFINEID_LOCAL_CARD && os(iOS)
    /// Result of one PACE-authenticated card hold or reader session.
    ///
    /// A rejected CAN remains distinct because RAPP must terminate that
    /// peer session immediately; neither a missing card nor an unrelated
    /// card failure proves rejection.
    internal enum CardSessionResult<Payload: Sendable>: Sendable {
      case connected(Payload)
      case failed
      case wrongCardAccessNumber
    }
  #endif

  internal enum ConnectionSnapshotResult: Sendable {
    case connected(Snapshot)
    case failed
    case wrongCardAccessNumber
  }

  internal enum ConnectionFailure: Error {
    case failed
    case wrongCardAccessNumber
  }

  internal enum Outcome: Equatable, Sendable {
    case alreadyActivated
    case failed
    case floorRefused(RetryFloorVerdict)
    case invalidated
    case invalidEntry
    case noCard
    case pinBlocked
    case rejected(remaining: RetryCount)
    case success
  }

  internal final class UncheckedCard: @unchecked Sendable {
    internal let card: TKSmartCard

    internal init(_ card: TKSmartCard) {
      self.card = card
    }
  }

  /// Runs `work` on the card over `transport`.
  ///
  /// Over the phone's own antenna the sheet draws the meter of
  /// `operation`: the card found, the secure channel, then the
  /// operation's own steps, finished or broken at the step `failedStep`
  /// names for the answer (nil when the answer is a success).
  ///
  /// `opener` names what opens a sealed card: the card access number, and
  /// for an organization card the PIN the operation spends.
  internal static func onCard<Answer: Sendable>(
    transport: Transport,
    opener: CardOpener<Answer>,
    operation: NearFieldOperation,
    failedStep: @escaping @Sendable (Answer) -> NearFieldStep?,
    _ work: @escaping @Sendable (CardOperations) -> Answer
  ) async -> Answer? {
    switch transport {
    case .reader:
      return await onReader(opener: opener, work)

    case .nearField:
      #if REFINEID_LOCAL_CARD && os(iOS)
        guard SupportedCardTransports.offersNearField else { return nil }
        let held: NearFieldCardSession
        do {
          held = try await NearFieldCardSession.open(showing: operation)
        } catch {
          return nil
        }
        defer { held.end() }
        let sheet = held.meter(operation)
        return await withCheckedContinuation { continuation in
          DispatchQueue.global(qos: .userInitiated).async {
            let answer = try? held.withCardSession { channel -> Answer? in
              answer(openedOperations(over: channel, opener: opener), refused: opener.refused) {
                operations in
                sheet.advance()
                return work(operations)
              }
            }
            switch answer.flatMap(\.self) {
            case .some(let answered):
              if let broken = failedStep(answered) {
                sheet.fail(at: broken)
              } else {
                sheet.finish()
              }
              continuation.resume(returning: answered)

            case .none:
              sheet.fail(at: nil)
              continuation.resume(returning: nil)
            }
          }
        }
      #else
        return nil
      #endif
    }
  }

  /// Runs `work` on the card in an attached reader.
  internal static func onReader<Answer: Sendable>(
    _ work: @escaping @Sendable (CardOperations) -> Answer?
  ) async -> Answer? {
    let nested: Answer?? = await onReader(opener: .cardAccessNumber(nil), work)
    return nested.flatMap(\.self)
  }

  /// Establishes the first PACE channel while preserving a rejected CAN
  /// as a distinct, recoverable result.
  internal static func connectionOperations(
    over channel: SmartCardChannel,
    cardAccessNumber: String?
  ) throws -> CardOperations {
    let operations = CardOperations(channel: channel)
    do {
      try operations.selectFineidApplication()
      return operations
    } catch {
      guard
        let cardAccessNumber,
        let offered = CardAccessNumber(digits: cardAccessNumber)
      else {
        throw ConnectionFailure.wrongCardAccessNumber
      }
      let keys: PaceSessionKeys
      do {
        keys = try PaceEstablishment(channel: channel)
          .establish(with: PacePassword(cardAccessNumber: offered)).keys
      } catch PaceEstablishment.Failure.authenticationTokenMismatch {
        throw ConnectionFailure.wrongCardAccessNumber
      } catch PaceEstablishment.Failure.cardRejected(.authenticationFailed) {
        // A FINEID card may reject the terminal's final PACE token with
        // 6300 instead of returning its own token for local comparison.
        // Both outcomes mean the CAN-derived session keys did not match.
        throw ConnectionFailure.wrongCardAccessNumber
      } catch {
        throw ConnectionFailure.failed
      }
      let secure = SecureMessagingChannel(wrapping: channel, sessionKeys: keys)
      let secureOperations = CardOperations(channel: secure)
      guard (try? secureOperations.selectFineidApplication()) != nil else {
        throw ConnectionFailure.failed
      }
      return secureOperations
    }
  }

  private static func onReader<Answer: Sendable>(
    opener: CardOpener<Answer>,
    _ operation: @escaping @Sendable (CardOperations) -> Answer
  ) async -> Answer? {
    guard let manager = TKSmartCardSlotManager.default else { return nil }
    let occupied = await CardSlotSearch.allOccupied(in: manager).filter { occupiedSlot in
      CardTransport.transport(forSlotNamed: occupiedSlot.name) == .reader
    }
    let cards = occupied.compactMap { occupiedSlot in
      occupiedSlot.slot.makeSmartCard().map(UncheckedCard.init)
    }
    guard !cards.isEmpty else { return nil }
    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        for candidate in cards {
          let answer = try? SmartCardChannel(candidate.card).withSession {
            channel -> Answer? in
            answer(
              openedOperations(over: channel, opener: opener), refused: opener.refused, operation)
          }
          if let value = answer.flatMap(\.self) {
            continuation.resume(returning: value)
            return
          }
        }
        continuation.resume(returning: nil)
      }
    }
  }

  internal static func selectedOperations(
    over channel: SmartCardChannel,
    cardAccessNumber: String?
  ) -> CardOperations? {
    let opener = CardOpener<Never>.cardAccessNumber(cardAccessNumber)
    guard case .opened(let operations) = openedOperations(over: channel, opener: opener) else {
      return nil
    }
    return operations
  }

  internal static func outcome(of error: Error) -> Outcome {
    switch error {
    case CardOperationError.pinRejected(let remaining):
      .rejected(remaining: remaining)

    case CardOperationError.pinBlocked:
      .pinBlocked

    case CardOperationError.credentialInvalidated:
      .invalidated

    case CardOperationError.pinLengthRefused:
      .invalidEntry

    default:
      .failed
    }
  }
}
