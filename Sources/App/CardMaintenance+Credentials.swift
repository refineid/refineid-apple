// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Foundation

extension CardMaintenance {
  internal struct Snapshot: Equatable, Sendable {
    internal let report: CredentialProbeReport?
    internal let activationNeeds: ActivationNeeds?
    internal let activationScheme: ActivationScheme?
    /// The card's answer to reset where the transport exposes it.
    internal var answerToReset = Data()
  }

  internal struct MutationReport: Equatable, Sendable {
    internal let outcome: Outcome
    internal let snapshot: Snapshot?
  }

  /// The credential acted on and the credential whose restored retry
  /// allowance confirms the mutation.
  private struct CredentialFloor {
    fileprivate let role: CredentialRole
    fileprivate let confirming: CredentialRole
  }

  internal static func snapshot(
    transport: Transport,
    cardAccessNumber: String?
  ) async -> Snapshot? {
    if await DemoMode.shared.isActive {
      return await DemoMode.shared.maintenanceSnapshot()
    }
    return await onCard(
      transport: transport,
      cardAccessNumber: cardAccessNumber,
      operation: .cardStatus,
      failedStep: Self.failedStep(of:)
    ) { operations in
      snapshot(on: operations)
    }
  }

  /// Reads only the three credential retry counters.
  ///
  /// Reader insertion uses this narrow probe for the shared health key. It
  /// deliberately skips activation classification, certificate reads, and all
  /// mutation paths so presenting identity remains independent of this status.
  internal static func credentialReport(
    transport: Transport,
    cardAccessNumber: String?
  ) async -> CredentialProbeReport? {
    if await DemoMode.shared.isActive {
      return await DemoMode.shared.credentialReport()
    }
    return await onCard(
      transport: transport,
      cardAccessNumber: cardAccessNumber,
      operation: .cardStatus,
      failedStep: Self.failedStep(of:)
    ) { operations in
      try? operations.probeCredentials()
    }
    .flatMap(\.self)
  }

  /// Determines the activation generation without probing credentials.
  ///
  /// The activation scheme of the card in a reader, from its
  /// authentication certificate's issue date, without reading any
  /// retry counter.
  internal static func readerActivationScheme() async -> ActivationScheme? {
    if await DemoMode.shared.isActive {
      return await DemoMode.shared.readerActivationScheme()
    }
    return await onReader { operations in
      classifyScheme(operations)
    }
  }

  internal static func changePin1(
    current: String,
    new: String,
    transport: Transport,
    cardAccessNumber: String?
  ) async -> MutationReport {
    if await DemoMode.shared.isActive {
      return await DemoMode.shared.changePIN1(current: current, new: new)
    }
    return await withFloor(
      CredentialFloor(role: .pin1, confirming: .pin1),
      transport: transport,
      cardAccessNumber: cardAccessNumber,
      operation: .changePin1
    ) { operations in
      guard
        let currentPin = Pin1(digits: current),
        let newPin = Pin1(digits: new)
      else {
        return .invalidEntry
      }
      do {
        try operations.changePin1(
          current: currentPin.consumeForSingleTransmission(),
          new: newPin.consumeForSingleTransmission()
        )
        return .success
      } catch {
        return outcome(of: error)
      }
    }
  }

  internal static func changePin2(
    current: String,
    new: String,
    transport: Transport,
    cardAccessNumber: String?
  ) async -> MutationReport {
    if await DemoMode.shared.isActive {
      return await DemoMode.shared.changePIN2(current: current, new: new)
    }
    return await withFloor(
      CredentialFloor(role: .pin2, confirming: .pin2),
      transport: transport,
      cardAccessNumber: cardAccessNumber,
      operation: .changePin2
    ) { operations in
      guard
        let currentPin = Pin2(digits: current),
        let newPin = Pin2(digits: new)
      else {
        return .invalidEntry
      }
      do {
        try operations.changePin2(
          current: currentPin.consumeForSingleTransmission(),
          new: newPin.consumeForSingleTransmission()
        )
        return .success
      } catch {
        return outcome(of: error)
      }
    }
  }

  internal static func unblockPin1(
    puk: String,
    new: String,
    transport: Transport,
    cardAccessNumber: String?
  ) async -> MutationReport {
    if await DemoMode.shared.isActive {
      return await DemoMode.shared.resetPIN1(puk: puk, new: new)
    }
    return await withFloor(
      CredentialFloor(role: .puk, confirming: .pin1),
      transport: transport,
      cardAccessNumber: cardAccessNumber,
      operation: .resetPin1
    ) { operations in
      guard let key = Puk(digits: puk), let pin = Pin1(digits: new) else {
        return .invalidEntry
      }
      do {
        try operations.unblockPin1(
          puk: key.consumeForSingleTransmission(),
          new: pin.consumeForSingleTransmission()
        )
        return .success
      } catch {
        return outcome(of: error)
      }
    }
  }

  internal static func unblockPin2(
    puk: String,
    new: String,
    transport: Transport,
    cardAccessNumber: String?
  ) async -> MutationReport {
    if await DemoMode.shared.isActive {
      return await DemoMode.shared.resetPIN2(puk: puk, new: new)
    }
    return await withFloor(
      CredentialFloor(role: .puk, confirming: .pin2),
      transport: transport,
      cardAccessNumber: cardAccessNumber,
      operation: .resetPin2
    ) { operations in
      guard let key = Puk(digits: puk), let pin = Pin2(digits: new) else {
        return .invalidEntry
      }
      do {
        try operations.unblockPin2(
          puk: key.consumeForSingleTransmission(),
          new: pin.consumeForSingleTransmission()
        )
        return .success
      } catch {
        return outcome(of: error)
      }
    }
  }

  private static func withFloor(
    _ floor: CredentialFloor,
    transport: Transport,
    cardAccessNumber: String?,
    operation: NearFieldOperation,
    _ mutation: @escaping @Sendable (CardOperations) -> Outcome
  ) async -> MutationReport {
    let result = await onCard(
      transport: transport,
      cardAccessNumber: cardAccessNumber,
      operation: operation,
      failedStep: Self.failedStep(of:)
    ) { operations -> MutationReport in
      guard let probe = try? operations.probeRetryCounter(role: floor.role) else {
        return MutationReport(
          outcome: .floorRefused(.refuseUnreadable),
          snapshot: snapshot(on: operations)
        )
      }
      let verdict = RetryFloor.evaluate(probeOutcome: probe)
      guard verdict == .proceed else {
        return MutationReport(
          outcome: .floorRefused(verdict),
          snapshot: snapshot(on: operations)
        )
      }
      let outcome = mutation(operations)
      let resultingSnapshot = snapshot(on: operations)
      let confirmedOutcome =
        outcome == .success && !confirmsRestored(floor.confirming, in: resultingSnapshot)
        ? .failed
        : outcome
      return MutationReport(
        outcome: confirmedOutcome,
        snapshot: resultingSnapshot
      )
    }
    return result ?? MutationReport(outcome: .noCard, snapshot: nil)
  }

  /// A successful CHANGE REFERENCE DATA or RESET RETRY COUNTER restores the
  /// target credential's retry allowance.
  ///
  /// Never turn the command status word into a success notice when the
  /// card's immediate state contradicts it.
  private static func confirmsRestored(
    _ role: CredentialRole,
    in snapshot: Snapshot
  ) -> Bool {
    let outcome: RetryProbeOutcome? =
      switch role {
      case .pin1:
        snapshot.report?.pin1

      case .pin2:
        snapshot.report?.pin2

      case .puk:
        snapshot.report?.puk
      }
    return switch outcome {
    case .remaining(let count):
      count.attemptsRemaining == RetryCount.pristineAllowance

    case .verified:
      true

    case .invalidated, .locked, .noInformation, .other, .none:
      false
    }
  }

  /// Where on the meter a status read broke: at the reads behind the
  /// secure channel when the counters stayed unread.
  private static func failedStep(of snapshot: Snapshot) -> NearFieldStep? {
    snapshot.report == nil ? .certificate : nil
  }

  /// Where on the meter a counter read broke: at the reads behind the
  /// secure channel when it read nothing.
  private static func failedStep(of report: CredentialProbeReport?) -> NearFieldStep? {
    report == nil ? .certificate : nil
  }

  /// Where on the meter a PIN change or reset broke: at the credential
  /// whenever it did not succeed.
  private static func failedStep(of report: MutationReport) -> NearFieldStep? {
    report.outcome == .success ? nil : .credential
  }

  internal static func snapshot(on operations: CardOperations) -> Snapshot {
    let scheme = classifyScheme(operations)
    let needs = scheme.map { activationScheme in
      operations.activationNeeds(scheme: activationScheme)
    }
    let report = try? operations.probeCredentials()
    return Snapshot(report: report, activationNeeds: needs, activationScheme: scheme)
  }
}
