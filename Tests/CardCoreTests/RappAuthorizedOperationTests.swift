// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine
  @Suite
  internal struct RappAuthorizedOperationTests {
    // MARK: Nested Types

    /// What the custodian saw of a read.
    private struct ReadProgress: Equatable {
      var prerequisites = 0
      var approvals = 0
      var safeReads = 0
    }

    // MARK: Static Properties

    /// A synthetic certificate; the custodian relays the card's bytes
    /// without reading them.
    private static let certificate = Data("synthetic authentication certificate".utf8)

    // MARK: Static Functions

    /// Answers a certificate read as the custodian does: the read skips
    /// consent and runs as soon as its prerequisites are done (RAPP
    /// v26.10.22 §8.2 item 6).
    private static func answerCertificateRead(
      _ coordinator: RappConnectionCoordinator
    ) async throws -> ReadProgress {
      var progress = ReadProgress()
      for await event in coordinator.events {
        switch event {
        case .established:
          break

        case .inspectPrerequisites(let operationID, let operation):
          #expect(operation.kind == .readAuthenticationCertificate)
          progress.prerequisites += 1
          try await coordinator.prerequisitesComplete(operationID: operationID)

        case .awaitUserApproval:
          progress.approvals += 1

        case .executeSafeRead(let operationID, _):
          progress.safeReads += 1
          try await coordinator.completeCertificate(operationID: operationID, der: certificate)
          return progress

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.connectionClosed(reason)

        case .executeCardCommand, .completed, .terminal, .progress, .cardStatus, .operationEnded,
          .answered:
          throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    /// Answers a certificate read, then waits for the custodian's own word
    /// that the read is over; true when that word names the read answered.
    private static func answerAndAwaitAnswered(
      _ coordinator: RappConnectionCoordinator
    ) async throws -> Bool {
      var answeredRead: RappOperationIdentifier?
      for await event in coordinator.events {
        switch event {
        case .inspectPrerequisites(let operationID, _):
          try await coordinator.prerequisitesComplete(operationID: operationID)

        case .executeSafeRead(let operationID, _):
          answeredRead = operationID
          try await coordinator.completeCertificate(operationID: operationID, der: certificate)

        case .answered(let operationID):
          return operationID == answeredRead

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.connectionClosed(reason)

        case .established, .awaitUserApproval, .executeCardCommand, .completed, .terminal,
          .progress, .cardStatus, .operationEnded:
          break
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    /// Reads the authentication certificate once the session is
    /// established.
    private static func readCertificate(
      _ coordinator: RappConnectionCoordinator
    ) async throws -> RappOperationResult {
      for await event in coordinator.events {
        switch event {
        case .established:
          try await coordinator.beginReadCertificate(
            signatureCertificate: false,
            expiresAfterMilliseconds: RappIntegrationFixtures.FixtureTiming
              .operationExpiryMilliseconds)

        case .cardStatus, .progress:
          break

        case .completed(_, let result):
          return result

        case .terminal(_, let reason):
          throw RappIntegrationFixtures.TestFailure.operationTerminated(reason)

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.connectionClosed(reason)

        case .inspectPrerequisites, .awaitUserApproval, .executeSafeRead, .executeCardCommand,
          .operationEnded, .answered:
          throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    // MARK: Functions

    @Test(arguments: [
      RappIntegrationFixtures.RequestedOperation.browserAuthentication(
        origin: "https://example.invalid"),
      RappIntegrationFixtures.RequestedOperation.documentSigning(
        documentName: "Review document.pdf",
        digest: Data(SHA256.hash(data: Data("Review document contents".utf8)))),
    ])
    internal func anAuthorizedSignatureExecutesOnceAndDeliversItsResult(
      operation: RappIntegrationFixtures.RequestedOperation
    ) async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      let connection = try await RappIntegrationConnectionSupport.makeConnection(fixture)

      let requesterOutcome = Task {
        try await RappIntegrationConnectionSupport.awaitCompletion(
          connection.requester, operation: operation)
      }
      let proxyOutcome = Task {
        try await RappIntegrationAuthorizationSupport.authorizeAndComplete(
          connection.proxy, operation: operation, signature: RappIntegrationFixtures.signature)
      }
      defer {
        requesterOutcome.cancel()
        proxyOutcome.cancel()
      }

      await connection.proxy.start()
      await connection.requester.start()
      let result = try await requesterOutcome.value
      let progress = try await proxyOutcome.value

      #expect(result == .signature(RappIntegrationFixtures.signature))
      #expect(
        progress
          == RappIntegrationFixtures.ProxyProgress(
            prerequisites: 1,
            approvals: 1,
            executions: 1
          ))
      #expect(
        try fixture.requesterVault.pairIsRevoked(
          pairID: fixture.requesterSummary.pairID) == false)
      #expect(
        try fixture.proxyVault.pairIsRevoked(
          pairID: fixture.proxySummary.pairID) == false)
      await connection.requester.close()
      await connection.proxy.close()
    }

    /// A certificate read is answered without asking the holder.
    @Test
    internal func aCertificateReadSkipsConsent() async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      let connection = try await RappIntegrationConnectionSupport.makeConnection(fixture)

      let requesterOutcome = Task { try await Self.readCertificate(connection.requester) }
      let proxyOutcome = Task { try await Self.answerCertificateRead(connection.proxy) }
      defer {
        requesterOutcome.cancel()
        proxyOutcome.cancel()
      }

      await connection.proxy.start()
      await connection.requester.start()
      let result = try await requesterOutcome.value
      let progress = try await proxyOutcome.value

      #expect(result == .certificate(Self.certificate))
      #expect(progress == ReadProgress(prerequisites: 1, approvals: 0, safeReads: 1))
      await connection.requester.close()
      await connection.proxy.close()
    }

    /// Answering a read ends it on the custodian's side, so the session is
    /// idle for the next dial instead of busy for good.
    @Test
    internal func answeringAReadTellsTheCustodianItIsOver() async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      let connection = try await RappIntegrationConnectionSupport.makeConnection(fixture)

      let requesterOutcome = Task { try await Self.readCertificate(connection.requester) }
      let proxyOutcome = Task { try await Self.answerAndAwaitAnswered(connection.proxy) }
      defer {
        requesterOutcome.cancel()
        proxyOutcome.cancel()
      }

      await connection.proxy.start()
      await connection.requester.start()
      #expect(try await requesterOutcome.value == .certificate(Self.certificate))
      #expect(try await proxyOutcome.value)
      await connection.requester.close()
      await connection.proxy.close()
    }
  }
#endif
