// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Dispatch
import Foundation

extension CardMaintenance {
  // MARK: - Types

  /// The outcome of reading a travel-document file under PACE.
  internal enum TravelDocumentResult<Payload: Sendable>: Sendable {
    case success(Payload)
    case wrongCardAccessNumber
    case cardUnavailable
    case failed
  }

  // MARK: - Static Methods

  /// Runs one travel-document operation over an attached reader or NFC after PACE.
  internal static func onTravelDocumentCard<Payload: Sendable>(
    cardAccessNumber: CardAccessNumber,
    _ operation: @escaping @Sendable (CardOperations) -> Payload?
  ) async -> TravelDocumentResult<Payload> {
    if let result = await onReaderTravelDocumentCard(
      cardAccessNumber: cardAccessNumber,
      operation
    ) {
      return result
    }

    #if REFINEID_LOCAL_CARD && os(iOS)
      if let result = await onNearFieldTravelDocumentCard(
        cardAccessNumber: cardAccessNumber,
        operation
      ) {
        return result
      }
    #endif

    return .cardUnavailable
  }

  private static func onReaderTravelDocumentCard<Payload: Sendable>(
    cardAccessNumber: CardAccessNumber,
    _ operation: @escaping @Sendable (CardOperations) -> Payload?
  ) async -> TravelDocumentResult<Payload>? {
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
          let answer = runTravelDocumentReaderSession(
            candidate: candidate,
            cardAccessNumber: cardAccessNumber,
            operation
          )
          switch answer {
          case .success, .wrongCardAccessNumber:
            continuation.resume(returning: answer)
            return
          case .failed, .cardUnavailable:
            break
          }
        }
        continuation.resume(returning: .failed)
      }
    }
  }

  #if REFINEID_LOCAL_CARD && os(iOS)
    private static func onNearFieldTravelDocumentCard<Payload: Sendable>(
      cardAccessNumber: CardAccessNumber,
      _ operation: @escaping @Sendable (CardOperations) -> Payload?
    ) async -> TravelDocumentResult<Payload>? {
      guard SupportedCardTransports.offersNearField else { return nil }
      let held: NearFieldCardSession
      do {
        held = try await NearFieldCardSession.open(message: CardPriming.holdMessage)
      } catch {
        return .cardUnavailable
      }
      defer { held.end() }
      return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          let answer: TravelDocumentResult<Payload>? = try? held.withCardSession { channel in
            executeTravelDocumentSession(
              over: channel,
              cardAccessNumber: cardAccessNumber,
              operation
            )
          }
          continuation.resume(returning: answer ?? .failed)
        }
      }
    }
  #endif

  private static func runTravelDocumentReaderSession<Payload: Sendable>(
    candidate: UncheckedCard,
    cardAccessNumber: CardAccessNumber,
    _ operation: @escaping @Sendable (CardOperations) -> Payload?
  ) -> TravelDocumentResult<Payload> {
    do {
      return try SmartCardChannel(candidate.card).withSession { channel in
        executeTravelDocumentSession(
          over: channel,
          cardAccessNumber: cardAccessNumber,
          operation
        )
      }
    } catch {
      return .cardUnavailable
    }
  }

  private static func executeTravelDocumentSession<Payload: Sendable>(
    over channel: SmartCardChannel,
    cardAccessNumber: CardAccessNumber,
    _ operation: (CardOperations) -> Payload?
  ) -> TravelDocumentResult<Payload> {
    try? CardOperations(channel: channel).selectMainFile()
    let keys: PaceSessionKeys
    do {
      keys = try PaceEstablishment(channel: channel).establish(with: cardAccessNumber)
    } catch PaceEstablishment.Failure.authenticationTokenMismatch {
      return .wrongCardAccessNumber
    } catch PaceEstablishment.Failure.cardRejected(.authenticationFailed) {
      return .wrongCardAccessNumber
    } catch {
      return .failed
    }
    let secure = SecureMessagingChannel(wrapping: channel, sessionKeys: keys)
    let operations = CardOperations(channel: secure)
    guard (try? operations.selectTravelDocumentApplication()) != nil else {
      return .failed
    }
    if let payload = operation(operations) {
      return .success(payload)
    }
    return .failed
  }
}
