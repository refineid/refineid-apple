// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  /// Ending a pairing and ending a session, over two real coordinators
  /// (RAPP v26.10.21 §4.5, §4.6, §8.1 item 3).
  extension RappIntegrationTests {
    // MARK: Static Functions

    /// Runs one session over the fixture's pairing until both sides close
    /// it, and answers with why each did.
    private static func closesOfOneSession(
      _ fixture: RappIntegrationFixtures.PairingFixture
    ) async throws -> (
      requester: RappConnectionCoordinator.CloseReason,
      proxy: RappConnectionCoordinator.CloseReason
    ) {
      let connection = try await RappIntegrationConnectionSupport.makeConnection(fixture)
      let requesterEvents = Task {
        await RappIntegrationConnectionSupport.eventsUntilClosed(connection.requester)
      }
      let proxyEvents = Task {
        await RappIntegrationConnectionSupport.eventsUntilClosed(connection.proxy)
      }
      defer {
        requesterEvents.cancel()
        proxyEvents.cancel()
      }
      await connection.proxy.start()
      await connection.requester.start()
      return (
        requester: try closeReason(of: await requesterEvents.value),
        proxy: try closeReason(of: await proxyEvents.value)
      )
    }

    private static func closeReason(
      of events: [RappConnectionCoordinator.Event]
    ) throws -> RappConnectionCoordinator.CloseReason {
      guard case .closed(let reason)? = events.last else {
        throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
      }
      return reason
    }

    /// The custodian's inspection of the requester's operation, answering
    /// with its identifier.
    private static func awaitInspection(
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

    /// Destroys the record on both sides, as each does once the close was
    /// delivered or received, and checks nothing of it is left.
    private static func revokeBothRecords(
      _ fixture: RappIntegrationFixtures.PairingFixture
    ) throws {
      let clock = RappPlatformClock()
      try RappPairRevocation.revoke(
        pairID: fixture.requesterSummary.pairID, in: fixture.requesterVault, clock: clock)
      try RappPairRevocation.revoke(
        pairID: fixture.proxySummary.pairID, in: fixture.proxyVault, clock: clock)
      #expect(try fixture.requesterVault.loadPair(pairID: fixture.requesterSummary.pairID) == nil)
      #expect(try fixture.proxyVault.loadPair(pairID: fixture.proxySummary.pairID) == nil)
      #expect(try fixture.requesterVault.activePairIDs().isEmpty)
      #expect(try fixture.proxyVault.activePairIDs().isEmpty)
    }

    // MARK: Functions

    /// A requester that forgot the pairing with no session open tells the
    /// custodian on the next session, in place of anything else; both
    /// sides then destroy the record.
    @Test
    internal func aRequesterForgottenPairingIsDeliveredOnTheNextSession() async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      let pairID = fixture.requesterSummary.pairID
      let requesterCatalog = RappPairCatalog(vault: fixture.requesterVault)
      try await requesterCatalog.forget(pairID: pairID)
      #expect(try await requesterCatalog.activePairs().isEmpty)

      let closes = try await Self.closesOfOneSession(fixture)

      #expect(closes.requester == .handshake(.revocationNoticeDelivered))
      #expect(closes.proxy == .operation(.pairRevoked))
      #expect(closes.proxy.peerRevokedPairing)
      try Self.revokeBothRecords(fixture)
    }

    /// A custodian that forgot the pairing with no session open answers
    /// the next session with the `pairing_revoked` close in place of
    /// `session.ready`.
    @Test
    internal func aCustodianForgottenPairingIsDeliveredInPlaceOfReady() async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      let pairID = fixture.proxySummary.pairID
      let proxyCatalog = RappPairCatalog(vault: fixture.proxyVault)
      try await proxyCatalog.forget(pairID: pairID)
      #expect(try await proxyCatalog.activePairs().isEmpty)

      let closes = try await Self.closesOfOneSession(fixture)

      #expect(closes.proxy == .handshake(.revocationNoticeDelivered))
      #expect(closes.requester == .handshake(.pairRevoked))
      #expect(closes.requester.peerRevokedPairing)
      try Self.revokeBothRecords(fixture)
    }

    /// Forgetting with a session open closes it with `pairing_revoked`;
    /// the peer learns at once.
    @Test
    internal func forgettingDuringASessionClosesItWithPairingRevoked() async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      let connection = try await RappIntegrationConnectionSupport.makeConnection(fixture)

      await connection.proxy.start()
      await connection.requester.start()
      try await RappIntegrationConnectionSupport.awaitEstablished(connection.requester)
      try await RappIntegrationConnectionSupport.awaitEstablished(connection.proxy)
      #expect(await connection.requester.closePairingRevoked(), "the close left")

      let requesterEvents = await RappIntegrationConnectionSupport.eventsUntilClosed(
        connection.requester)
      let proxyEvents = await RappIntegrationConnectionSupport.eventsUntilClosed(
        connection.proxy)
      #expect(requesterEvents == [.closed(.operation(.terminalFrameReleased))])
      #expect(proxyEvents == [.closed(.operation(.pairRevoked))])
      #expect(
        await !connection.requester.closePairingRevoked(),
        "a closed connection tells the peer nothing")
    }

    /// A local close reports the operation that ended with the session, then
    /// finishes the connection: its event stream ends and it takes no more
    /// operations.
    @Test
    internal func localCloseReportsTheEndedOperationAndFinishes() async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      let connection = try await RappIntegrationConnectionSupport.makeConnection(fixture)
      let operation = RappIntegrationFixtures.RequestedOperation.browserAuthentication(
        origin: "https://closed.example.invalid")

      await connection.proxy.start()
      await connection.requester.start()
      try await RappIntegrationConnectionSupport.awaitEstablished(connection.requester)
      try await RappIntegrationConnectionSupport.awaitEstablished(connection.proxy)
      try await operation.begin(on: connection.requester)
      let operationID = try await Self.awaitInspection(connection.proxy)
      await connection.proxy.close()

      let custodianSeen = await RappIntegrationConnectionSupport.eventsUntilClosed(
        connection.proxy)
      #expect(custodianSeen == [.operationEnded(.dropped(operationID)), .closed(.localRequest)])
      await #expect(throws: RappOperationDriver.LocalError.self) {
        _ = try await connection.proxy.operationDriver()
      }
    }

    /// A custodian that stops serving ends the session; both ends learn that
    /// the operation the card was not yet commanded for is dropped, and the
    /// pairing stays.
    @Test
    internal func serviceWithdrawnDropsTheLiveOperationAndKeepsThePairing() async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      let connection = try await RappIntegrationConnectionSupport.makeConnection(fixture)
      let operation = RappIntegrationFixtures.RequestedOperation.browserAuthentication(
        origin: "https://withdrawn.example.invalid")

      await connection.proxy.start()
      await connection.requester.start()
      try await RappIntegrationConnectionSupport.awaitEstablished(connection.requester)
      try await RappIntegrationConnectionSupport.awaitEstablished(connection.proxy)
      try await operation.begin(on: connection.requester)
      let operationID = try await Self.awaitInspection(connection.proxy)
      await connection.proxy.closeServiceWithdrawn()

      let seen = await RappIntegrationConnectionSupport.eventsUntilClosed(connection.requester)
      #expect(
        seen == [
          .operationEnded(.dropped(operationID)),
          .closed(.operation(.serviceWithdrawn)),
        ])
      #expect(try Self.closeReason(of: seen).serviceWithdrawn)
      let custodianSeen = await RappIntegrationConnectionSupport.eventsUntilClosed(
        connection.proxy)
      #expect(
        custodianSeen == [
          .operationEnded(.dropped(operationID)),
          .closed(.operation(.terminalFrameReleased)),
        ])
      #expect(try fixture.requesterVault.loadPair(pairID: fixture.requesterSummary.pairID) != nil)
      #expect(try fixture.proxyVault.loadPair(pairID: fixture.proxySummary.pairID) != nil)
    }
  }
#endif
