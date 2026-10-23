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
      let proxy = try await RappTestPairingPhone.showing(
        fixturePairingCode, name: "Authorizer iPhone", servicePrefix: proxyPrefix,
        dropAfter: nil)
      let link = proxy.link
      let search = try RappPairingSearch<String>(
        options: RappPairingCoordinator.Options(
          code: fixturePairingCode,
          profiles: RappIntegrationFixtures.profiles,
          transportProfile: RappIntegrationFixtures.transportProfile,
          displayName: "Requester Mac",
          platform: "macOS",
          vault: requesterVault),
        remoteUseAvailable: { true },
        dial: { _ in link.dial() })
      await search.found("phone")

      let requesterSummary = try await awaitPair(search)
      let proxySummary = try paired(await proxy.close())
      return await RappIntegrationFixtures.PairingFixture(
        requesterVault: requesterVault,
        proxyVault: proxy.vault,
        requesterSummary: requesterSummary,
        proxySummary: proxySummary,
        requesterFrames: link.requesterSent,
        proxyFrames: link.custodianSent,
        requesterPrefix: requesterPrefix,
        proxyPrefix: proxyPrefix
      )
    }

    /// The pairing the requester's search made.
    private static func awaitPair(
      _ search: RappPairingSearch<String>
    ) async throws -> RappPairingCoordinator.PairSummary {
      for await event in search.events {
        if case .paired(let summary) = event { return summary }
      }
      throw RappIntegrationFixtures.TestFailure.pairingEndedWithoutRecord
    }

    /// The pairing among a custodian's outcomes.
    private static func paired(
      _ outcomes: [RappPairingCoordinator.Event]
    ) throws -> RappPairingCoordinator.PairSummary {
      for event in outcomes {
        if case .paired(let summary) = event { return summary }
      }
      throw RappIntegrationFixtures.TestFailure.pairingEndedWithoutRecord
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
