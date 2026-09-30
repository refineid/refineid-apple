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
    // MARK: Static Properties

    /// An empty CBOR map, which is what a candidate with no parameters is.
    private static let emptyCborMapByte: UInt8 = 0xA0
    private static let emptyParameters = Data([emptyCborMapByte])

    /// Long enough that no test races the offer's expiry.
    private static let offerLifetimeMilliseconds: UInt64 = 60_000

    internal let requesterVault: RappDeviceVault
    internal let proxyVault: RappDeviceVault
    internal let requesterPairID: Data
    internal let proxyPairID: Data
    internal let requesterPrefix: String
    internal let proxyPrefix: String

    /// The half that owns the offer and shows the code.
    private static func makeRequester(
      profiles: [String],
      transportProfile: String,
      candidateID: String,
      vault: RappDeviceVault,
      outbound: SignRelayFrameEndpoint
    ) throws -> RappPairingCoordinator {
      try RappPairingCoordinator.requester(
        profiles: profiles,
        candidates: [
          .init(
            profile: transportProfile,
            candidateID: candidateID,
            parametersCBOR: emptyParameters)
        ],
        selectedCandidateID: candidateID,
        offerLifetimeMilliseconds: offerLifetimeMilliseconds,
        displayName: "Requester",
        platform: "macOS",
        vault: vault,
        transport: RappClosureFrameTransport(
          sender: { frame in await outbound.send(frame) },
          closer: { await outbound.close() }),
        code: fixturePairingCode
      )
    }

    /// The half that answers an offer it was handed.
    private static func makeProxy(
      offerURI: String,
      candidateID: String,
      vault: RappDeviceVault,
      outbound: SignRelayFrameEndpoint
    ) throws -> RappPairingCoordinator {
      try RappPairingCoordinator.proxy(
        scannedOfferURI: offerURI,
        selectedCandidateID: candidateID,
        displayName: "Proxy",
        platform: "iOS",
        vault: vault,
        transport: RappClosureFrameTransport(
          sender: { frame in await outbound.send(frame) },
          closer: { await outbound.close() }),
        code: fixturePairingCode
      )
    }

    /// Runs the ceremony between two fresh vaults.
    internal static func make(
      profiles: [String],
      transportProfile: String,
      candidateID: String
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
      let requester = try makeRequester(
        profiles: profiles,
        transportProfile: transportProfile,
        candidateID: candidateID,
        vault: madeRequesterVault,
        outbound: requesterOutbound)
      let proxy = try makeProxy(
        offerURI: try #require(requester.offerURI),
        candidateID: candidateID,
        vault: madeProxyVault,
        outbound: proxyOutbound)
      await requesterOutbound.install { frame in await proxy.receive(frame) }
      await proxyOutbound.install { frame in await requester.receive(frame) }

      async let requesterSummary = approveAndAwaitPair(requester, profiles: profiles)
      async let proxySummary = approveAndAwaitPair(proxy, profiles: profiles)
      await proxy.transportConnected()
      await requester.transportConnected()

      return Self(
        requesterVault: madeRequesterVault,
        proxyVault: madeProxyVault,
        requesterPairID: try await requesterSummary.pairID,
        proxyPairID: try await proxySummary.pairID,
        requesterPrefix: madeRequesterPrefix,
        proxyPrefix: madeProxyPrefix
      )
    }

    private static func approveAndAwaitPair(
      _ coordinator: RappPairingCoordinator,
      profiles: [String]
    ) async throws -> RappPairingCoordinator.PairSummary {
      for await event in coordinator.events {
        switch event {
        case .reviewPeer:
          await coordinator.approve(grantedProfiles: profiles)

        case .paired(let summary):
          return summary

        case .closed(let reason):
          throw SignRelayPairingFailure.closed(String(describing: reason))

        case .offerReady, .offerRestored:
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
