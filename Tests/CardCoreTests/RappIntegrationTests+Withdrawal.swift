// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  /// A requester's withdrawal over two real coordinators (RAPP v26.10.29
  /// §4.5 items 8 and 9).
  extension RappIntegrationTests {
    // MARK: Static Functions

    /// The custodian's inspection of the requester's operation, answering
    /// with its identifier.
    private static func inspectedOperation(
      _ coordinator: RappConnectionCoordinator
    ) async throws -> RappOperationIdentifier {
      for await event in coordinator.events {
        switch event {
        case .inspectPrerequisites(let operationID, _):
          return operationID

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.connectionClosed(reason)

        default:
          throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    // MARK: Functions

    /// A requester that withdraws with a session open tells the custodian
    /// with `service_withdrawn`: the custodian's operation ends, it sends
    /// no close of its own, and both keep the pairing.
    @Test
    internal func aRequesterWithdrawalEndsTheCustodiansOperationAndKeepsThePairing() async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      let connection = try await RappIntegrationConnectionSupport.makeConnection(fixture)
      let operation = RappIntegrationFixtures.RequestedOperation.browserAuthentication(
        origin: "https://withdrawing.example.invalid")

      await connection.proxy.start()
      await connection.requester.start()
      try await RappIntegrationConnectionSupport.awaitEstablished(connection.requester)
      try await RappIntegrationConnectionSupport.awaitEstablished(connection.proxy)
      try await operation.begin(on: connection.requester)
      let operationID = try await Self.inspectedOperation(connection.proxy)
      let custodianSent = await connection.proxyOutbound.snapshot().frames.count
      #expect(await connection.requester.closeServiceWithdrawn(), "the close left")

      let custodianSeen = await RappIntegrationConnectionSupport.eventsUntilClosed(
        connection.proxy)
      #expect(
        custodianSeen == [
          .operationEnded(.dropped(operationID)),
          .closed(.operation(.serviceWithdrawn)),
        ])
      guard case .closed(let reason)? = custodianSeen.last else {
        throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
      }
      #expect(reason.serviceWithdrawn)
      #expect(!reason.peerRevokedPairing)
      #expect(await connection.proxyOutbound.snapshot().frames.count == custodianSent)
      let requesterSeen = await RappIntegrationConnectionSupport.eventsUntilClosed(
        connection.requester)
      #expect(requesterSeen.last == .closed(.operation(.terminalFrameReleased)))
      #expect(
        await !connection.requester.closeServiceWithdrawn(),
        "a closed connection tells the peer nothing")
      #expect(try fixture.requesterVault.loadPair(pairID: fixture.requesterSummary.pairID) != nil)
      #expect(try fixture.proxyVault.loadPair(pairID: fixture.proxySummary.pairID) != nil)
    }

    /// A requester that withdraws before its session is open closes the
    /// connection without a notice.
    @Test
    internal func aRequesterWithdrawalBeforeTheSessionIsOpenSendsNothing() async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      let connection = try await RappIntegrationConnectionSupport.makeConnection(fixture)

      #expect(await !connection.requester.closeServiceWithdrawn())

      let requesterSeen = await RappIntegrationConnectionSupport.eventsUntilClosed(
        connection.requester)
      #expect(requesterSeen == [.closed(.localRequest)])
      #expect(await connection.requesterOutbound.snapshot().frames.isEmpty)
      #expect(try fixture.requesterVault.loadPair(pairID: fixture.requesterSummary.pairID) != nil)
    }
  }
#endif
