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
      await RappReaderSessionHolder.shared.yield()
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

    /// The first wireless connection, classified for activation by the
    /// card's reference numbering and authentication certificate.
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
        held = try await NearFieldCardSession.open(showing: .cardStatus)
      } catch {
        return .failed
      }
      defer { held.end() }
      let sheet = held.meter(.cardStatus)
      return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          let answer = try? held.withCardSession { channel -> ConnectionSnapshotResult in
            let result = snapshotFromChannel(
              channel, cardAccessNumber: cardAccessNumber, sheet: sheet)
            guard case .connected(var snapshot) = result else { return result }
            snapshot.answerToReset = held.answerToReset
            return .connected(snapshot)
          }
          if case .connected = answer {
            sheet.finish()
          } else {
            sheet.fail(at: nil)
          }
          continuation.resume(returning: answer ?? .failed)
        }
      }
    }

    private static func readerConnectionSnapshot(
      cardAccessNumber: String?
    ) async -> ConnectionSnapshotResult? {
      guard let manager = TKSmartCardSlotManager.default else { return nil }
      await RappReaderSessionHolder.shared.yield()
      let occupied = await CardSlotSearch.allOccupied(in: manager).filter { candidate in
        CardTransport.transport(forSlotNamed: candidate.name) == .reader
      }
      guard !occupied.isEmpty else { return nil }
      let occupiedCards: [UncheckedCard] = occupied.compactMap { candidate in
        candidate.slot.makeSmartCard().map(UncheckedCard.init)
      }
      guard !occupiedCards.isEmpty else { return nil }
      return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          for candidate in occupiedCards {
            let answer = try? SmartCardChannel(candidate.card).withSession { channel in
              snapshotFromChannel(
                channel,
                cardAccessNumber: cardAccessNumber,
                sheet: nil
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

    /// The snapshot read over `channel`; `sheet`, when the phone's own
    /// antenna holds the card, moves past the secure channel once it is
    /// open.
    private static func snapshotFromChannel(
      _ channel: SmartCardChannel,
      cardAccessNumber: String?,
      sheet: NearFieldSheet?
    ) -> ConnectionSnapshotResult {
      do {
        let operations = try connectionOperations(
          over: channel,
          cardAccessNumber: cardAccessNumber)
        sheet?.advance()
        guard let activation = operations.activationClassification() else {
          return .failed
        }
        let needs = operations.activationNeeds(scheme: activation.scheme)
        let report = try? operations.probeCredentials()
        return .connected(
          Snapshot(
            report: report,
            activationNeeds: needs,
            activation: activation))
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
          held = try await NearFieldCardSession.open(showing: .cardStatus)
        } catch {
          return DebugModeReport(
            lines: ["activation-probe: NFC session did not open"],
            succeeded: false)
        }
        defer { held.end() }
        let sheet = held.meter(.cardStatus)
        return await withCheckedContinuation { continuation in
          DispatchQueue.global(qos: .userInitiated).async {
            let report = try? held.withCardSession { channel -> DebugModeReport in
              debugReportFromChannel(
                channel, cardAccessNumber: cardAccessNumber, sheet: sheet)
            }
            if report?.succeeded == true {
              sheet.finish()
            } else {
              sheet.fail(at: nil)
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
        sheet: NearFieldSheet
      ) -> DebugModeReport {
        do {
          let operations = try connectionOperations(
            over: channel,
            cardAccessNumber: cardAccessNumber)
          sheet.advance()
          let activation = operations.activationClassification()
          let pin1Record = try? operations.readPinChangeRecord(role: .pin1)
          let pin2Record = try? operations.readPinChangeRecord(role: .pin2)
          let pin1Probe = try? operations.probeRetryCounter(role: .pin1)
          let pin2Probe = try? operations.probeRetryCounter(role: .pin2)
          let selectedScheme = activation?.scheme
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
              "activation-probe: classification \(String(describing: activation))",
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
