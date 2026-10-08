// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import CryptoTokenKit
  import Dispatch
  import Foundation

  extension CardMaintenance {
    /// Runs one card operation on an occupied attached reader after PACE.
    internal static func onReaderCard<Payload: Sendable>(
      cardAccessNumber: String?,
      _ operation: @escaping @Sendable (CardOperations) -> Payload
    ) async -> CardSessionResult<Payload>? {
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
            guard
              let answer = runReaderSession(
                candidate: candidate,
                cardAccessNumber: cardAccessNumber,
                operation
              )
            else { continue }
            switch answer {
            case .connected, .wrongCardAccessNumber:
              continuation.resume(returning: answer)
              return
            case .failed:
              break
            }
          }
          continuation.resume(returning: .failed)
        }
      }
    }

    private static func runReaderSession<Payload: Sendable>(
      candidate: UncheckedCard,
      cardAccessNumber: String?,
      _ operation: @escaping @Sendable (CardOperations) -> Payload
    ) -> CardSessionResult<Payload>? {
      do {
        return try SmartCardChannel(candidate.card).withSession { channel in
          do {
            let operations = try connectionOperations(
              over: channel,
              cardAccessNumber: cardAccessNumber
            )
            return .connected(operation(operations))
          } catch ConnectionFailure.wrongCardAccessNumber {
            return .wrongCardAccessNumber
          } catch {
            return .failed
          }
        }
      } catch {
        return nil
      }
    }

    /// Runs one RAPP card operation in one exclusive NFC hold after PACE.
    internal static func onSecureNearFieldCard<Payload: Sendable>(
      cardAccessNumber: String?,
      message: String,
      _ operation: @escaping @Sendable (CardOperations) -> Payload
    ) async -> CardSessionResult<Payload> {
      guard let cardAccessNumber else {
        return .wrongCardAccessNumber
      }
      guard SupportedCardTransports.offersNearField else {
        #if DEBUG
          print("[near-field] refused: platform offers no antenna")
          fflush(stdout)
        #endif
        return .failed
      }
      let held: NearFieldCardSession
      do {
        held = try await NearFieldCardSession.open(message: message)
      } catch {
        #if DEBUG
          print("[near-field] open failed: \(String(describing: error))")
          fflush(stdout)
        #endif
        return .failed
      }
      defer { held.end() }
      return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          let answer = Self.cardSessionAnswer(held) { channel in
            do {
              let operations = try connectionOperations(
                over: channel,
                cardAccessNumber: cardAccessNumber
              )
              return CardSessionResult.connected(operation(operations))
            } catch ConnectionFailure.wrongCardAccessNumber {
              return CardSessionResult<Payload>.wrongCardAccessNumber
            } catch {
              #if DEBUG
                print("[near-field] connect failed: \(String(describing: error))")
                fflush(stdout)
              #endif
              return CardSessionResult<Payload>.failed
            }
          }
          continuation.resume(returning: answer ?? .failed)
        }
      }
    }

    private static func cardSessionAnswer<Payload: Sendable>(
      _ held: NearFieldCardSession,
      _ body: (SmartCardChannel) throws -> CardSessionResult<Payload>
    ) -> CardSessionResult<Payload>? {
      do {
        return try held.withCardSession(body)
      } catch {
        #if DEBUG
          print("[near-field] session failed: \(String(describing: error))")
          fflush(stdout)
        #endif
        return nil
      }
    }

    /// The first wireless connection, classified from the live ATR before
    /// falling back to the certificate.
    ///
    /// Unknown state is a failed connection, never evidence that the card is activated.
    internal static func connectionSnapshot(
      cardAccessNumber: String?
    ) async -> ConnectionSnapshotResult {
      if await DemoMode.shared.isActive, let cardAccessNumber {
        return await DemoMode.shared.connectionSnapshot(
          cardAccessNumber: cardAccessNumber)
      }
      if let readerResult = await readerConnectionSnapshot(cardAccessNumber: cardAccessNumber) {
        return readerResult
      }
      guard let cardAccessNumber else { return .failed }
      guard SupportedCardTransports.offersNearField else { return .failed }
      let held: NearFieldCardSession
      do {
        held = try await NearFieldCardSession.open(
          message: String(localized: "Hold the card near the top of the iPhone."))
      } catch {
        return .failed
      }
      defer { held.end() }
      let atrScheme = ActivationScheme.classify(answerToReset: held.answerToReset)
      return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          let answer = try? held.withCardSession { channel -> ConnectionSnapshotResult in
            let result = snapshotFromChannel(
              channel, cardAccessNumber: cardAccessNumber, atrScheme: atrScheme)
            guard case .connected(var snapshot) = result else { return result }
            snapshot.answerToReset = held.answerToReset
            return .connected(snapshot)
          }
          continuation.resume(returning: answer ?? .failed)
        }
      }
    }

    private static func readerConnectionSnapshot(
      cardAccessNumber: String?
    ) async -> ConnectionSnapshotResult? {
      guard let manager = TKSmartCardSlotManager.default else { return nil }
      let occupied = await CardSlotSearch.allOccupied(in: manager).filter { candidate in
        CardTransport.transport(forSlotNamed: candidate.name) == .reader
      }
      guard !occupied.isEmpty else { return nil }
      let occupiedCards: [(card: UncheckedCard, atrScheme: ActivationScheme?)] = occupied.compactMap
      { candidate in
        guard let card = candidate.slot.makeSmartCard() else { return nil }
        let atrScheme = candidate.slot.atr.flatMap { atr in
          ActivationScheme.classify(answerToReset: atr.bytes)
        }
        return (UncheckedCard(card), atrScheme)
      }
      guard !occupiedCards.isEmpty else { return nil }
      return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          for candidate in occupiedCards {
            let answer = try? SmartCardChannel(candidate.card.card).withSession { channel in
              snapshotFromChannel(
                channel,
                cardAccessNumber: cardAccessNumber,
                atrScheme: candidate.atrScheme
              )
            }
            switch answer {
            case .connected, .wrongCardAccessNumber:
              continuation.resume(returning: answer)
              return

            case .failed, .none:
              break
            }
          }
          continuation.resume(returning: .failed)
        }
      }
    }

    private static func snapshotFromChannel(
      _ channel: SmartCardChannel,
      cardAccessNumber: String?,
      atrScheme: ActivationScheme?
    ) -> ConnectionSnapshotResult {
      do {
        let operations = try connectionOperations(
          over: channel,
          cardAccessNumber: cardAccessNumber)
        let certificateScheme = classifyScheme(operations)
        guard let scheme = certificateScheme ?? atrScheme else {
          return .failed
        }
        let needs = operations.activationNeeds(scheme: scheme)
        let report = try? operations.probeCredentials()
        return .connected(
          Snapshot(
            report: report,
            activationNeeds: needs,
            activationScheme: scheme))
      } catch ConnectionFailure.wrongCardAccessNumber {
        return .wrongCardAccessNumber
      } catch {
        return .failed
      }
    }

    #if DEBUG
      internal static func debugActivationSignals() async -> DebugModeReport {
        guard let cardAccessNumber = CardCredentialStore.displayedCardAccessNumber() else {
          return DebugModeReport(
            lines: ["activation-probe: no card access number stored"],
            succeeded: false)
        }
        guard SupportedCardTransports.offersNearField else {
          return DebugModeReport(
            lines: ["activation-probe: near-field transport unavailable"],
            succeeded: false)
        }
        let held: NearFieldCardSession
        do {
          held = try await NearFieldCardSession.open(
            message: String(localized: "Hold the card near the top of the iPhone."))
        } catch {
          return DebugModeReport(
            lines: ["activation-probe: NFC session did not open"],
            succeeded: false)
        }
        defer { held.end() }
        let atrScheme = ActivationScheme.classify(answerToReset: held.answerToReset)
        return await withCheckedContinuation { continuation in
          DispatchQueue.global(qos: .userInitiated).async {
            let report = try? held.withCardSession { channel -> DebugModeReport in
              debugReportFromChannel(
                channel, cardAccessNumber: cardAccessNumber, atrScheme: atrScheme)
            }
            continuation.resume(
              returning: report.flatMap(\.self)
                ?? DebugModeReport(
                  lines: ["activation-probe: card session unavailable"],
                  succeeded: false))
          }
        }
      }

      private static func debugReportFromChannel(
        _ channel: SmartCardChannel,
        cardAccessNumber: String,
        atrScheme: ActivationScheme?
      ) -> DebugModeReport {
        do {
          let operations = try connectionOperations(
            over: channel,
            cardAccessNumber: cardAccessNumber)
          let certificateScheme = classifyScheme(operations)
          let pin1Record = try? operations.readPinChangeRecord(role: .pin1)
          let pin2Record = try? operations.readPinChangeRecord(role: .pin2)
          let pin1Probe = try? operations.probeRetryCounter(role: .pin1)
          let pin2Probe = try? operations.probeRetryCounter(role: .pin2)
          let selectedScheme = certificateScheme ?? atrScheme
          let pin1Readiness = selectedScheme.map { scheme in
            ActivationPreflight.evaluate(
              scheme: scheme,
              probe: pin1Probe,
              changeRecord: pin1Record ?? .unreadable)
          }
          let pin2Readiness = selectedScheme.map { scheme in
            ActivationPreflight.evaluate(
              scheme: scheme,
              probe: pin2Probe,
              changeRecord: pin2Record ?? .unreadable)
          }
          return DebugModeReport(
            lines: [
              "activation-probe: ATR scheme \(String(describing: atrScheme))",
              "activation-probe: certificate scheme \(String(describing: certificateScheme))",
              "activation-probe: PIN1 changed \(String(describing: pin1Record))",
              "activation-probe: PIN2 changed \(String(describing: pin2Record))",
              "activation-probe: PIN1 probe \(String(describing: pin1Probe))",
              "activation-probe: PIN2 probe \(String(describing: pin2Probe))",
              "activation-probe: PIN1 readiness \(String(describing: pin1Readiness))",
              "activation-probe: PIN2 readiness \(String(describing: pin2Readiness))",
            ],
            succeeded: selectedScheme != nil)
        } catch {
          return DebugModeReport(
            lines: ["activation-probe: card session failed: \(error)"],
            succeeded: false)
        }
      }
    #endif
  }
#else
  extension CardMaintenance {
    internal static func connectionSnapshot(
      cardAccessNumber _: String
    ) async -> ConnectionSnapshotResult {
      await withCheckedContinuation { continuation in
        continuation.resume(returning: .failed)
      }
    }
  }
#endif
