// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security
import Testing

@testable import CardCore

/// The six-digit code the two fixtures here key their CPace PAKE on.
private let fixturePairingCode = "246813"

#if canImport(RappEngine)
  import RappEngine
  /// A pairing made the way two devices make one, for tests that need a
  /// stored pair record on each side.
  internal struct SignRelayPairing {
    internal let requesterVault: RappDeviceVault
    internal let proxyVault: RappDeviceVault
    internal let requesterPairID: Data
    internal let proxyPairID: Data
    internal let requesterPrefix: String
    internal let proxyPrefix: String

    /// The options both halves share: the offer is derived from them.
    private static func options(
      role name: String,
      profiles: [String],
      transportProfile: String,
      vault: RappDeviceVault,
      outbound: SignRelayFrameEndpoint
    ) -> RappPairingCoordinator.Options {
      RappPairingCoordinator.Options(
        code: fixturePairingCode,
        profiles: profiles,
        transportProfile: transportProfile,
        displayName: name,
        platform: name == "Requester" ? "macOS" : "iOS",
        vault: vault,
        transport: RappClosureFrameTransport(
          sender: { frame in await outbound.send(frame) },
          closer: { await outbound.close() }))
    }

    /// Runs the ceremony between two fresh vaults.
    internal static func make(
      profiles: [String],
      transportProfile: String
    ) async throws -> Self {
      let testID = UUID().uuidString
      let madeRequesterPrefix = "fi.refineid.tests.slim.\(testID).requester"
      let madeProxyPrefix = "fi.refineid.tests.slim.\(testID).proxy"
      let madeRequesterVault = RappDeviceVault(
        accessGroup: nil, servicePrefix: madeRequesterPrefix)
      let madeProxyVault = RappDeviceVault(
        accessGroup: nil, servicePrefix: madeProxyPrefix)

      let requesterOutbound = SignRelayFrameEndpoint()
      let proxyOutbound = SignRelayFrameEndpoint()
      let requester = try RappPairingCoordinator.requester(
        options: options(
          role: "Requester", profiles: profiles, transportProfile: transportProfile,
          vault: madeRequesterVault, outbound: requesterOutbound))
      let proxy = try RappPairingCoordinator.custodian(
        options: options(
          role: "Proxy", profiles: profiles, transportProfile: transportProfile,
          vault: madeProxyVault, outbound: proxyOutbound))
      await requesterOutbound.install { frame in await proxy.receive(frame) }
      await proxyOutbound.install { frame in await requester.receive(frame) }

      async let requesterSummary = awaitPair(requester)
      async let proxySummary = awaitPair(proxy)
      // The requester waits for the offer the custodian serves on connecting.
      await requester.transportConnected()
      await proxy.transportConnected()

      return Self(
        requesterVault: madeRequesterVault,
        proxyVault: madeProxyVault,
        requesterPairID: try await requesterSummary.pairID,
        proxyPairID: try await proxySummary.pairID,
        requesterPrefix: madeRequesterPrefix,
        proxyPrefix: madeProxyPrefix
      )
    }

    private static func awaitPair(
      _ coordinator: RappPairingCoordinator
    ) async throws -> RappPairingCoordinator.PairSummary {
      for await event in coordinator.events {
        switch event {
        case .paired(let summary):
          return summary

        case .closed(let reason):
          throw SignRelayPairingFailure.closed(String(describing: reason))

        case .peerIntroduced, .offerRestored:
          continue
        }
      }
      throw SignRelayPairingFailure.endedWithoutRecord
    }

    // MARK: Functions

    /// Removes everything the ceremony stored.
    internal func deleteKeychainServices() {
      for prefix in [requesterPrefix, proxyPrefix] {
        for suffix in ["pair", "selection", "requester", "proxy"] {
          SecItemDelete(
            [
              kSecClass as String: kSecClassGenericPassword,
              kSecAttrService as String: "\(prefix).\(suffix)",
            ] as CFDictionary)
        }
      }
    }
  }

#endif
