// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine
  internal enum RappIntegrationAuthorizationSupport {
    // MARK: Static Functions
    private static func requireExpected(
      _ operation: RappOperationDriver.Operation,
      expected: RappIntegrationFixtures.RequestedOperation
    ) throws {
      guard expected.matches(operation) else {
        throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
      }
    }

    /// The failure an event that should not have come names.
    private static func ending(_ event: RappConnectionCoordinator.Event) -> any Error {
      switch event {
      case .terminal(_, let reason):
        RappIntegrationFixtures.TestFailure.operationTerminated(reason)

      case .closed(let reason):
        RappIntegrationFixtures.TestFailure.connectionClosed(reason)

      default:
        RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
      }
    }

    internal static func authorizeAndComplete(
      _ coordinator: RappConnectionCoordinator,
      operation expected: RappIntegrationFixtures.RequestedOperation,
      signature: Data
    ) async throws -> RappIntegrationFixtures.ProxyProgress {
      try await authorizeAndComplete(
        coordinator,
        operation: expected,
        signature: signature,
        cardHold: .zero
      )
    }

    /// Takes `expected` through inspection, consent and the card command,
    /// then answers with `signature`; the custodian is done once the result
    /// left, since nothing acknowledges it (RAPP v26.10.22 §8.2).
    internal static func authorizeAndComplete(
      _ coordinator: RappConnectionCoordinator,
      operation expected: RappIntegrationFixtures.RequestedOperation,
      signature: Data,
      cardHold: Duration
    ) async throws -> RappIntegrationFixtures.ProxyProgress {
      var progress = RappIntegrationFixtures.ProxyProgress()
      for await event in coordinator.events {
        switch event {
        case .established, .answered:
          // The custodian's own word that an earlier operation is over.
          break

        case .inspectPrerequisites(let operationID, let operation):
          try requireExpected(operation, expected: expected)
          progress.prerequisites += 1
          try await coordinator.prerequisitesComplete(operationID: operationID)

        case .awaitUserApproval(let operationID, let operation):
          try requireExpected(operation, expected: expected)
          progress.approvals += 1
          try await coordinator.approve(operationID: operationID)

        case .executeCardCommand(let operationID, let operation):
          try requireExpected(operation, expected: expected)
          progress.executions += 1
          // The antenna's share of the operation, where the custodian is
          // busy with the card and answers nothing but liveness.
          if cardHold > .zero {
            try await Task.sleep(for: cardHold)
          }
          try await coordinator.completeSignature(
            operationID: operationID,
            signature: signature
          )
          return progress

        case .terminal, .closed, .executeSafeRead, .completed, .progress, .cardStatus,
          .operationEnded:
          throw Self.ending(event)
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    /// Refuses at inspection when `termination` says so, else completes the
    /// inspection; true when the custodian is done.
    private static func refusesAtInspection(
      _ termination: RappIntegrationFixtures.ProxyTermination,
      operationID: RappOperationIdentifier,
      on coordinator: RappConnectionCoordinator
    ) async throws -> Bool {
      switch termination {
      case .retryFloor:
        try await coordinator.retryFloor(operationID: operationID)
        return true

      case .unsupportedRequest:
        try await coordinator.requestInvalidOrUnsupported(operationID: operationID)
        return true

      case .userDenied, .cardError, .operationFailed:
        try await coordinator.prerequisitesComplete(operationID: operationID)
        return false
      }
    }

    /// Denies when `termination` is a denial, else approves; true when the
    /// custodian is done.
    private static func decide(
      _ termination: RappIntegrationFixtures.ProxyTermination,
      operationID: RappOperationIdentifier,
      on coordinator: RappConnectionCoordinator
    ) async throws -> Bool {
      guard termination == .userDenied else {
        try await coordinator.approve(operationID: operationID)
        return false
      }
      try await coordinator.deny(operationID: operationID)
      return true
    }

    /// Reports the card command's failure.
    private static func failCardCommand(
      _ termination: RappIntegrationFixtures.ProxyTermination,
      operationID: RappOperationIdentifier,
      on coordinator: RappConnectionCoordinator
    ) async throws {
      switch termination {
      case .cardError:
        try await coordinator.cardError(operationID: operationID)

      case .operationFailed:
        try await coordinator.operationFailed(operationID: operationID)

      case .retryFloor, .unsupportedRequest, .userDenied:
        throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
      }
    }

    internal static func authorizeAndTerminate(
      _ coordinator: RappConnectionCoordinator,
      operation expected: RappIntegrationFixtures.RequestedOperation,
      termination: RappIntegrationFixtures.ProxyTermination
    ) async throws -> RappIntegrationFixtures.ProxyProgress {
      var progress = RappIntegrationFixtures.ProxyProgress()
      for await event in coordinator.events {
        switch event {
        case .established, .answered:
          // The custodian's own word that an earlier operation is over.
          break

        case .inspectPrerequisites(let operationID, let operation):
          try requireExpected(operation, expected: expected)
          progress.prerequisites += 1
          if try await refusesAtInspection(termination, operationID: operationID, on: coordinator) {
            return progress
          }

        case .awaitUserApproval(let operationID, let operation):
          try requireExpected(operation, expected: expected)
          progress.approvals += 1
          if try await decide(termination, operationID: operationID, on: coordinator) {
            return progress
          }

        case .executeCardCommand(let operationID, let operation):
          try requireExpected(operation, expected: expected)
          progress.executions += 1
          try await failCardCommand(termination, operationID: operationID, on: coordinator)
          return progress

        case .terminal, .closed, .executeSafeRead, .completed, .progress, .cardStatus,
          .operationEnded:
          throw Self.ending(event)
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    internal static func awaitPair(
      _ coordinator: RappPairingCoordinator
    ) async throws -> RappPairingCoordinator.PairSummary {
      for await event in coordinator.events {
        switch event {
        case .paired(let summary):
          return summary

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.pairingClosed(reason)

        case .keyConfirmed, .offerRestored, .peerIntroduced:
          break
        }
      }
      throw RappIntegrationFixtures.TestFailure.pairingEndedWithoutRecord
    }
  }
#endif
