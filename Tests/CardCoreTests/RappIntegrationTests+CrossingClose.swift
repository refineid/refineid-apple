// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  /// A close of another reason that crosses a requester's `pairing_revoked`
  /// close is not its echo (RAPP v26.11.2 §7.1 item 7, §4.6 item 6): the
  /// forgotten record stays in the backlog, on the handshake path and on an
  /// open session alike.
  extension RappIntegrationTests {
    /// Two drivers past the Noise handshake.
    private struct Handshaken {
      let requester: RappSessionDriver
      let proxy: RappSessionDriver
      /// The custodian's frames after its handshake answer, unread.
      let toRequester: [Data]
      /// What the requester sent once the handshake completed.
      let requesterSent: [Data]
    }

    // MARK: Static Functions

    /// The requester's and the custodian's records of the fixture's pairing.
    private static func records(
      _ fixture: RappIntegrationFixtures.PairingFixture
    ) throws -> (requester: RappPairRecord, proxy: RappPairRecord) {
      (
        requester: try RappPairRecord.loadFromVault(
          pairId: fixture.requesterSummary.pairID, vault: fixture.requesterVault),
        proxy: try RappPairRecord.loadFromVault(
          pairId: fixture.proxySummary.pairID, vault: fixture.proxyVault)
      )
    }

    /// The bytes of the one frame `commands` sends.
    private static func sent(_ commands: [RappSessionDriver.Command]) -> [Data] {
      commands.compactMap { command in
        if case .send(let frame) = command { return frame }
        return nil
      }
    }

    /// The frame of an operation driver's close in `commands`.
    private static func closeFrame(
      _ commands: [RappOperationDriver.Command]
    ) throws -> (frame: Data, release: RappOperationDriver.FrameRelease) {
      for command in commands {
        if case .send(let frame, let release) = command { return (frame, release) }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    /// Both drivers of the fixture's pairing through the Noise handshake:
    /// the custodian has sent `session.ready`, which comes back unread.
    private static func handshaken(
      _ requester: RappPairRecord, _ proxy: RappPairRecord
    ) async throws -> Handshaken {
      let name = try #require(RappDisplayName(PairRecordFixture.computerName))
      let profile = RappIntegrationFixtures.transportProfile
      let requesterDriver = try RappSessionDriver(
        role: .requester, pair: requester, displayName: name, transportProfile: profile)
      let proxyDriver = try RappSessionDriver(
        role: .proxy, pair: proxy, displayName: name, transportProfile: profile)
      let first = sent(await requesterDriver.start())
      #expect(await proxyDriver.start().isEmpty, "the custodian waits for the first message")
      let answer = sent(await proxyDriver.receive(try #require(first.first)))
      let responderHandshake = try #require(answer.first)
      return Handshaken(
        requester: requesterDriver, proxy: proxyDriver, toRequester: Array(answer.dropFirst()),
        requesterSent: sent(await requesterDriver.receive(responderHandshake)))
    }

    // MARK: Functions

    /// The custodian withdraws as the forgotten pairing's close goes out
    /// first in the session: the crossing close keeps the record.
    @Test
    internal func aCrossingWithdrawalIsNotTheRevocationEchoBeforeReady() async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      try await RappPairCatalog(vault: fixture.requesterVault)
        .forget(pairID: fixture.requesterSummary.pairID)
      let (requester, proxy) = try Self.records(fixture)
      let drivers = try await Self.handshaken(requester, proxy)
      #expect(drivers.requesterSent.count == 1, "the close is the first and only message")
      let operations = try await drivers.proxy.beginOperationDriver(
        maximumLifetimeMilliseconds: RappRequesterPolicy.interactive
          .maximumOperationLifetimeMilliseconds)
      let withdrawal = try Self.closeFrame(await operations.close(reason: .serviceWithdrawn))

      for ready in drivers.toRequester {
        let readyCommands = await drivers.requester.receive(ready)
        #expect(readyCommands.isEmpty, "the ready is not the echo")
      }
      let crossed = await drivers.requester.receive(withdrawal.frame)
      #expect(crossed == [.closed(.revocationNoticeUnacknowledged)])
      #expect(requester.metadata().forgottenAtMs != nil, "the record stays forgotten")
    }

    /// On an open session the requester's `pairing_revoked` close counts as
    /// heard only on its echo, not on a crossing withdrawal.
    @Test
    internal func aCrossingWithdrawalIsNotTheRevocationEchoInSession() async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      let (requester, proxy) = try Self.records(fixture)
      for crossing in [true, false] {
        let drivers = try await Self.handshaken(requester, proxy)
        var hello: [Data] = []
        for frame in drivers.toRequester {
          hello += Self.sent(await drivers.requester.receive(frame))
        }
        let lifetime = RappRequesterPolicy.interactive.maximumOperationLifetimeMilliseconds
        let requesterOperations = try await drivers.requester.beginOperationDriver(
          maximumLifetimeMilliseconds: lifetime)
        let proxyOperations = try await drivers.proxy.beginOperationDriver(
          maximumLifetimeMilliseconds: lifetime)
        for frame in hello {
          _ = await proxyOperations.receive(frame)
        }
        let revocation = try Self.closeFrame(
          await requesterOperations.close(reason: .pairingRevoked))
        _ = await requesterOperations.frameReleased(revocation.release, succeeded: true)
        let answer: Data
        if crossing {
          answer = try Self.closeFrame(await proxyOperations.close(reason: .serviceWithdrawn))
            .frame
        } else {
          answer = try Self.closeFrame(await proxyOperations.receive(revocation.frame)).frame
        }
        _ = await requesterOperations.receive(answer)
        let echoed = await requesterOperations.ownCloseEchoed
        #expect(
          echoed == !crossing,
          "only the pairing_revoked echo says the phone heard the close")
      }
    }
  }
#endif
