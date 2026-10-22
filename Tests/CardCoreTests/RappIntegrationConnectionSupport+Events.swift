// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  /// Following one coordinator's events to the outcome a test waits for.
  extension RappIntegrationConnectionSupport {
    /// Begins `operation` once the session is established and answers with
    /// its result.
    internal static func awaitCompletion(
      _ coordinator: RappConnectionCoordinator,
      operation: RappIntegrationFixtures.RequestedOperation
    ) async throws -> RappOperationResult {
      for await event in coordinator.events {
        switch event {
        case .cardStatus, .progress:
          break

        case .established:
          try await operation.begin(on: coordinator)

        case .completed(_, let result):
          return result

        case .terminal(_, let reason):
          throw RappIntegrationFixtures.TestFailure.operationTerminated(reason)

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.connectionClosed(reason)

        case .inspectPrerequisites, .awaitUserApproval, .executeSafeRead,
          .executeCardCommand, .operationEnded:
          throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    /// Runs `operation` to its terminal event and answers with the
    /// registered error it carried.
    internal static func awaitTerminal(
      _ coordinator: RappConnectionCoordinator,
      operation: RappIntegrationFixtures.RequestedOperation
    ) async throws -> RappTerminalReason {
      for await event in coordinator.events {
        switch event {
        case .cardStatus, .progress:
          break

        case .established:
          try await operation.begin(on: coordinator)

        case .terminal(_, let reason):
          return reason

        case .completed(_, let result):
          throw RappIntegrationFixtures.TestFailure.unexpectedResult(result)

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.connectionClosed(reason)

        case .inspectPrerequisites, .awaitUserApproval, .executeSafeRead,
          .executeCardCommand, .operationEnded:
          throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    /// Begins `operation` on an established session and answers with its
    /// result.
    internal static func complete(
      _ operation: RappIntegrationFixtures.RequestedOperation,
      on coordinator: RappConnectionCoordinator
    ) async throws -> RappOperationResult {
      try await operation.begin(on: coordinator)
      for await event in coordinator.events {
        switch event {
        case .cardStatus, .progress:
          break

        case .completed(_, let result):
          return result

        case .terminal(_, let reason):
          throw RappIntegrationFixtures.TestFailure.operationTerminated(reason)

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.connectionClosed(reason)

        case .established, .inspectPrerequisites, .awaitUserApproval, .executeSafeRead,
          .executeCardCommand, .operationEnded:
          throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    /// The first `count` card statuses the requester hears.
    internal static func awaitCardStatuses(
      _ coordinator: RappConnectionCoordinator,
      count: Int
    ) async throws -> [RappCardStatus] {
      var heard: [RappCardStatus] = []
      for await event in coordinator.events {
        switch event {
        case .established:
          break

        case .cardStatus(let status):
          heard.append(status)
          if heard.count == count { return heard }

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.connectionClosed(reason)

        default:
          throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    /// Waits for the session to establish, skipping nothing else.
    internal static func awaitEstablished(_ coordinator: RappConnectionCoordinator) async throws {
      for await event in coordinator.events {
        switch event {
        case .established:
          return

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.connectionClosed(reason)

        default:
          throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    /// Collects every event up to and including the close.
    internal static func eventsUntilClosed(
      _ coordinator: RappConnectionCoordinator
    ) async -> [RappConnectionCoordinator.Event] {
      var seen: [RappConnectionCoordinator.Event] = []
      for await event in coordinator.events {
        seen.append(event)
        if case .closed = event { break }
      }
      return seen
    }
  }
#endif
