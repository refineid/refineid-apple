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
      message: String(localized: "Hold the card near the top of the iPhone.")
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
      message: ""
    ) { operations in
      try? operations.probeCredentials()
    }
    .flatMap(\.self)
  }

  /// Determines the activation generation without probing credentials.
  ///
  /// A reader ATR normally answers immediately and is sufficient for
  /// every MultiApp generation. The certificate fallback covers a
  /// documented card whose ATR is not in the generation table, still
  /// without reading any retry counter.
  internal static func readerActivationScheme() async -> ActivationScheme? {
    if await DemoMode.shared.isActive {
      return await DemoMode.shared.readerActivationScheme()
    }
    guard let manager = TKSmartCardSlotManager.default else { return nil }
    let occupied = await CardSlotSearch.allOccupied(in: manager).filter { candidate in
      CardTransport.transport(forSlotNamed: candidate.name) == .reader
    }
    for candidate in occupied {
      guard let answerToReset = candidate.slot.atr?.bytes else { continue }
      if let scheme = ActivationScheme.classify(answerToReset: answerToReset) {
        return scheme
      }
    }
    return await onCard(
      transport: .reader,
      cardAccessNumber: nil,
      message: ""
    ) { operations in
      classifyScheme(operations)
    }
    .flatMap(\.self)
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
      message: String(localized: "Hold the card still while PIN 1 is changed.")
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
      message: String(localized: "Hold the card still while PIN 2 is changed.")
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
      message: String(localized: "Hold the card still while PIN 1 is reset.")
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
      message: String(localized: "Hold the card still while PIN 2 is reset.")
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
    message: String,
    _ operation: @escaping @Sendable (CardOperations) -> Outcome
  ) async -> MutationReport {
    let result = await onCard(
      transport: transport,
      cardAccessNumber: cardAccessNumber,
      message: message
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
      let outcome = operation(operations)
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

  internal static func snapshot(on operations: CardOperations) -> Snapshot {
    let scheme = classifyScheme(operations)
    let needs = scheme.map { activationScheme in
      operations.activationNeeds(scheme: activationScheme)
    }
    let report = try? operations.probeCredentials()
    return Snapshot(report: report, activationNeeds: needs, activationScheme: scheme)
  }
}
