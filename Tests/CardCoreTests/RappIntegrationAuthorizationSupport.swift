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

    private static func applyTermination(
      _ termination: RappIntegrationFixtures.ProxyTermination,
      operationID: Data,
      coordinator: RappConnectionCoordinator,
      progress: inout RappIntegrationFixtures.ProxyProgress
    ) async throws {
      switch termination {
      case .cardRemovedBeforeTransmit:
        try await coordinator.cardRemovedBeforeTransmit(operationID: operationID)

      case .cardCompletionAmbiguous:
        progress.executions += 1
        try await coordinator.cardCompletionAmbiguous(operationID: operationID)

      case .userDenied, .retryPolicyRefused:
        throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
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
        cardHoldMilliseconds: 0
      )
    }

    internal static func authorizeAndComplete(
      _ coordinator: RappConnectionCoordinator,
      operation expected: RappIntegrationFixtures.RequestedOperation,
      signature: Data,
      cardHoldMilliseconds: UInt64
    ) async throws -> RappIntegrationFixtures.ProxyProgress {
      var progress = RappIntegrationFixtures.ProxyProgress()
      for await event in coordinator.events {
        switch event {
        case .established:
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
          // The antenna's share of the operation, where the proxy is busy
          // with the card and answers nothing else.
          if cardHoldMilliseconds > 0 {
            try await Task.sleep(for: .milliseconds(cardHoldMilliseconds))
          }
          try await coordinator.completeSignature(
            operationID: operationID,
            signature: signature
          )

        case .operationFinished:
          progress.acknowledgments += 1
          return progress

        case .terminal(_, _, let reason):
          throw RappIntegrationFixtures.TestFailure.operationTerminated(reason)

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.connectionClosed(reason)

        case .executeSafeRead, .completed, .advisoryCancellation,
          .peerBusy, .peerUnknownOperation, .progress:
          throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    internal static func authorizeAndRejectCredential(
      _ coordinator: RappConnectionCoordinator,
      operation expected: RappIntegrationFixtures.RequestedOperation
    ) async throws -> RappIntegrationFixtures.ProxyProgress {
      var progress = RappIntegrationFixtures.ProxyProgress()
      for await event in coordinator.events {
        switch event {
        case .established:
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
          try await coordinator.credentialRejected(operationID: operationID)
          return progress

        case .terminal(_, _, let reason):
          throw RappIntegrationFixtures.TestFailure.operationTerminated(reason)

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.connectionClosed(reason)

        case .executeSafeRead, .completed, .advisoryCancellation,
          .operationFinished, .peerBusy, .peerUnknownOperation, .progress:
          throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    internal static func authorizeAndTerminate(
      _ coordinator: RappConnectionCoordinator,
      operation expected: RappIntegrationFixtures.RequestedOperation,
      termination: RappIntegrationFixtures.ProxyTermination
    ) async throws -> RappIntegrationFixtures.ProxyProgress {
      var progress = RappIntegrationFixtures.ProxyProgress()
      for await event in coordinator.events {
        switch event {
        case .established:
          break

        case .inspectPrerequisites(let operationID, let operation):
          try requireExpected(operation, expected: expected)
          progress.prerequisites += 1
          if termination == .retryPolicyRefused {
            try await coordinator.retryRefused(operationID: operationID)
            return progress
          }
          try await coordinator.prerequisitesComplete(operationID: operationID)

        case .awaitUserApproval(let operationID, let operation):
          try requireExpected(operation, expected: expected)
          progress.approvals += 1
          if termination == .userDenied {
            try await coordinator.deny(operationID: operationID)
            return progress
          }
          try await coordinator.approve(operationID: operationID)

        case .executeCardCommand(let operationID, let operation):
          try requireExpected(operation, expected: expected)
          try await applyTermination(
            termination,
            operationID: operationID,
            coordinator: coordinator,
            progress: &progress
          )
          return progress

        case .terminal(_, _, let reason):
          throw RappIntegrationFixtures.TestFailure.operationTerminated(reason)

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.connectionClosed(reason)

        case .executeSafeRead, .completed, .advisoryCancellation,
          .operationFinished, .peerBusy, .peerUnknownOperation, .progress:
          throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    internal static func approveAndAwaitPair(
      _ coordinator: RappPairingCoordinator,
      profiles: [String]
    ) async throws -> RappPairingCoordinator.PairSummary {
      for await event in coordinator.events {
        switch event {
        case .reviewPeer:
          await coordinator.approve(grantedProfiles: profiles)

        case .paired(let summary):
          return summary

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.pairingClosed(reason)

        case .offerReady, .offerRestored:
          break
        }
      }
      throw RappIntegrationFixtures.TestFailure.pairingEndedWithoutRecord
    }
  }
#endif
