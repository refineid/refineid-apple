// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security
import Testing

@testable import CardCore

/// The code the custodian shows and the requester types.
private let fixturePairingCode = "246813"

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
        try await RappIntegrationAuthorizationSupport.awaitPair(requester)
      }
      let proxyOutcome = Task {
        try await RappIntegrationAuthorizationSupport.awaitPair(proxy)
      }
      defer {
        requesterOutcome.cancel()
        proxyOutcome.cancel()
      }

      // The requester waits for the offer the custodian serves on connecting.
      await requester.transportConnected()
      await proxy.transportConnected()
      return try await (requesterOutcome.value, proxyOutcome.value)
    }

    private static func pairingOptions(
      displayName: String,
      platform: String,
      vault: RappDeviceVault,
      transport: RappClosureFrameTransport
    ) -> RappPairingCoordinator.Options {
      RappPairingCoordinator.Options(
        code: fixturePairingCode,
        profiles: RappIntegrationFixtures.profiles,
        transportProfile: RappIntegrationFixtures.transportProfile,
        displayName: displayName,
        platform: platform,
        vault: vault,
        transport: transport
      )
    }

    private static func makePairingRequester(
      vault: RappDeviceVault,
      transport: RappClosureFrameTransport
    ) throws -> RappPairingCoordinator {
      try RappPairingCoordinator.requester(
        options: pairingOptions(
          displayName: "Requester Mac", platform: "macOS", vault: vault, transport: transport))
    }

    private static func makePairingProxy(
      vault: RappDeviceVault,
      transport: RappClosureFrameTransport
    ) throws -> RappPairingCoordinator {
      try RappPairingCoordinator.custodian(
        options: pairingOptions(
          displayName: "Authorizer iPhone", platform: "iOS", vault: vault, transport: transport))
    }

    internal static func makeConnection(
      _ fixture: RappIntegrationFixtures.PairingFixture
    ) async throws -> RappIntegrationFixtures.ConnectionFixture {
      try await makeConnection(
        requesterPair: try RappPairRecord.loadFromVault(
          pairId: fixture.requesterSummary.pairID,
          vault: fixture.requesterVault
        ),
        proxyPair: try RappPairRecord.loadFromVault(
          pairId: fixture.proxySummary.pairID,
          vault: fixture.proxyVault
        )
      )
    }

    /// Two coordinators over the two halves of one pairing, wired to each
    /// other; neither has started.
    internal static func makeConnection(
      requesterPair: RappPairRecord,
      proxyPair: RappPairRecord
    ) async throws -> RappIntegrationFixtures.ConnectionFixture {
      let requesterOutbound = RappIntegrationFixtures.FrameEndpoint()
      let proxyOutbound = RappIntegrationFixtures.FrameEndpoint()
      let requester = try RappConnectionCoordinator(
        role: .requester,
        pair: requesterPair,
        transport: RappClosureFrameTransport(
          sender: { frame in try await requesterOutbound.send(frame) },
          closer: { await requesterOutbound.close() }
        ),
        maximumLifetimeMilliseconds: RappIntegrationFixtures.FixtureTiming
          .connectionMaximumLifetimeMilliseconds,
        transportProfile: RappIntegrationFixtures.transportProfile
      )
      let proxy = try RappConnectionCoordinator(
        role: .proxy,
        pair: proxyPair,
        transport: RappClosureFrameTransport(
          sender: { frame in try await proxyOutbound.send(frame) },
          closer: { await proxyOutbound.close() }
        ),
        maximumLifetimeMilliseconds: RappIntegrationFixtures.FixtureTiming
          .connectionMaximumLifetimeMilliseconds,
        transportProfile: RappIntegrationFixtures.transportProfile
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

    internal static func deleteKeychainServices(for fixture: RappIntegrationFixtures.PairingFixture)
    {
      deleteKeychainServices(prefix: fixture.requesterPrefix)
      deleteKeychainServices(prefix: fixture.proxyPrefix)
    }

    internal static func deleteKeychainServices(prefix: String) {
      for suffix in ["pair", "selection"] {
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
