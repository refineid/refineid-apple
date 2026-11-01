// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) || os(macOS)

  import CardCore

  extension DemoMode {
    // MARK: Static Properties

    /// The virtual card lists no lengths, so every credential takes its
    /// FINEID bounds.
    internal static let pinLengths = CardPinLengths.notListed(numbering: .citizen)

    // MARK: Static Functions

    internal static func maintenanceSnapshot(
      from snapshot: VirtualIDCard.Snapshot,
      retryReport: VirtualIDCard.RetryReport?,
      report suppliedReport: CredentialProbeReport?
    ) -> CardMaintenance.Snapshot {
      let report =
        suppliedReport
        ?? retryReport.map(Self.report(from:))
        ?? Self.report(from: snapshot.card)
      return CardMaintenance.Snapshot(
        report: report,
        activationNeeds: CardActivationNeeds(
          pin1: snapshot.card.pin1.isFactoryValue,
          pin2: snapshot.card.pin2.isFactoryValue),
        activation: .citizen(snapshot.card.activationScheme),
        pinLengths: pinLengths)
    }

    internal static func report(
      from card: VirtualIDCard.CardState
    ) -> CredentialProbeReport {
      CredentialProbeReport(
        pin1: retryOutcome(card.pin1.attemptsRemaining),
        pin2: retryOutcome(card.pin2.attemptsRemaining),
        puk: retryOutcome(card.puk.attemptsRemaining))
    }

    internal static func report(
      from report: VirtualIDCard.RetryReport
    ) -> CredentialProbeReport {
      CredentialProbeReport(
        pin1: retryOutcome(report.pin1),
        pin2: retryOutcome(report.pin2),
        puk: retryOutcome(report.puk))
    }

    internal static func retryOutcome(_ attempts: UInt8) -> RetryProbeOutcome {
      guard let count = RetryCount(attemptsRemaining: attempts) else {
        return .noInformation
      }
      return count.isBlocked ? .locked : .remaining(count)
    }

    internal static func outcome(
      from outcome: VirtualIDCard.CredentialOutcome
    ) -> CardMaintenance.Outcome {
      switch outcome {
      case .success:
        .success

      case .alreadyActivated:
        .alreadyActivated

      case .invalidEntry:
        .invalidEntry

      case .blocked:
        .pinBlocked

      case .rejected(let remaining):
        RetryCount(attemptsRemaining: remaining)
          .map { .rejected(remaining: $0) }
          ?? .failed

      case .refusedLowAttempts:
        .floorRefused(.refuseLowAttempts)

      case .transportFailure(let effect):
        switch effect {
        case .connectionLost, .readerDisconnected, .cardRemoved:
          .noCard

        case .timeout, .malformedResponse, .tokenNotPublished:
          .failed
        }
      }
    }
  }

#endif
