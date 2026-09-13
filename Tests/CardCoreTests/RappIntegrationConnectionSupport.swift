// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine
  internal enum RappIntegrationConnectionSupport {
    // MARK: Static Functions
    internal static func makePairedFixture() async throws -> RappIntegrationFixtures.PairingFixture
    {
      let testID = UUID().uuidString
      let requesterPrefix = "fi.refineid.tests.rapp.\(testID).requester"
      let proxyPrefix = "fi.refineid.tests.rapp.\(testID).proxy"
      let requesterVault = RappDeviceVault(
        accessGroup: nil,
        servicePrefix: requesterPrefix
      )
      let proxyVault = RappDeviceVault(
        accessGroup: nil,
        servicePrefix: proxyPrefix
      )
      let requesterOutbound = RappIntegrationFixtures.FrameEndpoint()
      let proxyOutbound = RappIntegrationFixtures.FrameEndpoint()
      let requesterTransport = RappClosureFrameTransport(
        sender: { frame in try await requesterOutbound.send(frame) },
        closer: { await requesterOutbound.close() }
      )
      let proxyTransport = RappClosureFrameTransport(
        sender: { frame in try await proxyOutbound.send(frame) },
        closer: { await proxyOutbound.close() }
      )
      let requester = try makePairingRequester(
        vault: requesterVault,
        transport: requesterTransport
      )
      let proxy = try makePairingProxy(
        scannedOfferURI: try #require(requester.offerURI),
        vault: proxyVault,
        transport: proxyTransport
      )
      await requesterOutbound.install { frame in await proxy.receive(frame) }
      await proxyOutbound.install { frame in await requester.receive(frame) }

      let outcomes = try await approvePairedOutcomes(
        requester: requester,
        proxy: proxy
      )
      return await RappIntegrationFixtures.PairingFixture(
        requesterVault: requesterVault,
        proxyVault: proxyVault,
        requesterSummary: outcomes.requester,
        proxySummary: outcomes.proxy,
        requesterFrames: requesterOutbound.snapshot(),
        proxyFrames: proxyOutbound.snapshot(),
        requesterPrefix: requesterPrefix,
        proxyPrefix: proxyPrefix
      )
    }

    private static func approvePairedOutcomes(
      requester: RappPairingCoordinator,
      proxy: RappPairingCoordinator
    ) async throws -> (
      requester: RappPairingCoordinator.PairSummary,
      proxy: RappPairingCoordinator.PairSummary
    ) {
      let requesterOutcome = Task {
        try await RappIntegrationAuthorizationSupport.approveAndAwaitPair(
          requester, profiles: RappIntegrationFixtures.profiles
        )
      }
      let proxyOutcome = Task {
        try await RappIntegrationAuthorizationSupport.approveAndAwaitPair(
          proxy, profiles: RappIntegrationFixtures.profiles
        )
      }
      defer {
        requesterOutcome.cancel()
        proxyOutcome.cancel()
      }

      await proxy.transportConnected()
      await requester.transportConnected()
      return try await (requesterOutcome.value, proxyOutcome.value)
    }

    private static func makePairingRequester(
      vault: RappDeviceVault,
      transport: RappClosureFrameTransport
    ) throws -> RappPairingCoordinator {
      try RappPairingCoordinator.requester(
        profiles: RappIntegrationFixtures.profiles,
        candidates: [
          .init(
            profile: RappIntegrationFixtures.transportProfile,
            candidateID: RappIntegrationFixtures.candidateID,
            parametersCBOR: RappIntegrationFixtures.FixtureTiming.emptyParametersCBOR
          )
        ],
        selectedCandidateID: RappIntegrationFixtures.candidateID,
        offerLifetimeMilliseconds: RappIntegrationFixtures.FixtureTiming
          .pairingOfferLifetimeMilliseconds,
        displayName: "Requester Mac",
        platform: "macOS",
        vault: vault,
        transport: transport
      )
    }

    private static func makePairingProxy(
      scannedOfferURI: String,
      vault: RappDeviceVault,
      transport: RappClosureFrameTransport
    ) throws -> RappPairingCoordinator {
      try RappPairingCoordinator.proxy(
        scannedOfferURI: scannedOfferURI,
        selectedCandidateID: RappIntegrationFixtures.candidateID,
        displayName: "Authorizer iPhone",
        platform: "iOS",
        vault: vault,
        transport: transport
      )
    }

    internal static func makeConnection(
      _ fixture: RappIntegrationFixtures.PairingFixture
    ) async throws -> RappIntegrationFixtures.ConnectionFixture {
      try await makeConnection(fixture, liveness: RappIntegrationFixtures.liveness)
    }

    internal static func makeConnection(
      _ fixture: RappIntegrationFixtures.PairingFixture,
      liveness: RappOperationDriver.Liveness
    ) async throws -> RappIntegrationFixtures.ConnectionFixture {
      let requesterPair = try RappPairRecord.loadFromVault(
        pairId: fixture.requesterSummary.pairID,
        vault: fixture.requesterVault
      )
      let proxyPair = try RappPairRecord.loadFromVault(
        pairId: fixture.proxySummary.pairID,
        vault: fixture.proxyVault
      )
      let requesterOutbound = RappIntegrationFixtures.FrameEndpoint()
      let proxyOutbound = RappIntegrationFixtures.FrameEndpoint()
      let requester = try RappConnectionCoordinator(
        role: .requester,
        pair: requesterPair,
        vault: fixture.requesterVault,
        transport: RappClosureFrameTransport(
          sender: { frame in try await requesterOutbound.send(frame) },
          closer: { await requesterOutbound.close() }
        ),
        maximumLifetimeMilliseconds: RappIntegrationFixtures.FixtureTiming
          .connectionMaximumLifetimeMilliseconds,
        liveness: liveness
      )
      let proxy = try RappConnectionCoordinator(
        role: .proxy,
        pair: proxyPair,
        vault: fixture.proxyVault,
        transport: RappClosureFrameTransport(
          sender: { frame in try await proxyOutbound.send(frame) },
          closer: { await proxyOutbound.close() }
        ),
        maximumLifetimeMilliseconds: RappIntegrationFixtures.FixtureTiming
          .connectionMaximumLifetimeMilliseconds,
        liveness: liveness
      )
      await requesterOutbound.install { frame in await proxy.receive(frame) }
      await proxyOutbound.install { frame in await requester.receive(frame) }
      return RappIntegrationFixtures.ConnectionFixture(
        requester: requester,
        proxy: proxy,
        requesterOutbound: requesterOutbound,
        proxyOutbound: proxyOutbound
      )
    }

    internal static func awaitCompletion(
      _ coordinator: RappConnectionCoordinator,
      operation: RappIntegrationFixtures.RequestedOperation
    ) async throws -> RappOperationDriver.Result {
      for await event in coordinator.events {
        switch event {
        case .established:
          try await operation.begin(on: coordinator)

        case .completed(_, let result):
          return result

        case .terminal(_, _, let reason):
          throw RappIntegrationFixtures.TestFailure.operationTerminated(reason)

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.connectionClosed(reason)

        case .inspectPrerequisites, .awaitUserApproval, .executeSafeRead,
          .executeCardCommand, .advisoryCancellation, .operationFinished,
          .peerBusy, .peerUnknownOperation, .progress:
          throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    internal static func awaitTerminal(
      _ coordinator: RappConnectionCoordinator,
      operation: RappIntegrationFixtures.RequestedOperation
    ) async throws -> RappOperationDriver.TerminalReason? {
      for await event in coordinator.events {
        switch event {
        case .established:
          try await operation.begin(on: coordinator)

        case .terminal(_, _, let reason):
          return reason

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.connectionClosed(reason)

        case .inspectPrerequisites, .awaitUserApproval, .executeSafeRead,
          .executeCardCommand, .completed, .advisoryCancellation,
          .operationFinished, .peerBusy, .peerUnknownOperation, .progress:
          throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    internal static func deleteKeychainServices(for fixture: RappIntegrationFixtures.PairingFixture)
    {
      deleteKeychainServices(
        prefix: fixture.requesterPrefix,
        pairID: fixture.requesterSummary.pairID
      )
      deleteKeychainServices(
        prefix: fixture.proxyPrefix,
        pairID: fixture.proxySummary.pairID
      )
    }

    internal static func deleteKeychainServices(prefix: String, pairID: Data) {
      let pairHex = pairID.map { String(format: "%02x", $0) }.joined()
      for suffix in [
        "pair",
        "selection",
        "requester.\(pairHex)",
        "proxy.\(pairHex)",
      ] {
        let query: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: "\(prefix).\(suffix)",
          kSecUseDataProtectionKeychain as String: KeychainPlatform.usesDataProtection,
          kSecAttrSynchronizable as String: false,
        ]
        SecItemDelete(query as CFDictionary)
      }
    }
  }
#endif
