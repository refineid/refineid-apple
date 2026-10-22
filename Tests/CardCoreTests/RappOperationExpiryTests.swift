// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  /// An operation whose deadline passes before the card was commanded is
  /// cancelled, and the custodian's owner hears it is over, so its prompt
  /// comes down and the card goes to the next operation (RAPP v26.10.22
  /// §8.1 item 2, §8.2 item 2).
  @Suite
  internal struct RappOperationExpiryTests {
    /// A deadline the custodian's liveness poll passes at once.
    private static let shortExpiryMilliseconds: UInt64 = 200

    /// Asks for a certificate with a deadline that passes while the
    /// custodian holds it, and answers how the operation ended.
    private static func requestAndAwaitEnd(
      _ coordinator: RappConnectionCoordinator
    ) async throws -> RappTerminalReason {
      for await event in coordinator.events {
        switch event {
        case .established:
          try await coordinator.beginReadCertificate(
            signatureCertificate: false, expiresAfterMilliseconds: shortExpiryMilliseconds)

        case .terminal(_, let reason):
          return reason

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.connectionClosed(reason)

        case .completed(_, let result):
          throw RappIntegrationFixtures.TestFailure.unexpectedResult(result)

        case .cardStatus, .progress, .inspectPrerequisites, .awaitUserApproval,
          .executeSafeRead, .executeCardCommand, .operationEnded, .answered:
          break
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    /// Holds the admitted operation without serving it, as a custodian
    /// whose card is busy with another session's operation does, and
    /// answers whether the operation it held is the one reported over.
    private static func holdAndAwaitAnswered(
      _ coordinator: RappConnectionCoordinator
    ) async throws -> Bool {
      var held: RappOperationIdentifier?
      for await event in coordinator.events {
        switch event {
        case .inspectPrerequisites(let operationID, _):
          held = operationID

        case .answered(let operationID):
          return operationID == held

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.connectionClosed(reason)

        case .established, .awaitUserApproval, .executeSafeRead, .executeCardCommand,
          .completed, .terminal, .progress, .cardStatus, .operationEnded:
          break
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    @Test
    internal func anOperationThatExpiresWaitingIsReportedOver() async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      let connection = try await RappIntegrationConnectionSupport.makeConnection(fixture)

      let requesterOutcome = Task { try await Self.requestAndAwaitEnd(connection.requester) }
      let proxyOutcome = Task { try await Self.holdAndAwaitAnswered(connection.proxy) }
      defer {
        requesterOutcome.cancel()
        proxyOutcome.cancel()
      }

      await connection.proxy.start()
      await connection.requester.start()
      #expect(try await requesterOutcome.value == .operationExpired)
      #expect(try await proxyOutcome.value)
      await connection.requester.close()
      await connection.proxy.close()
    }
  }
#endif
