// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  @Suite("RAPP 6-digit pairing code and ceremony")
  internal struct RappPairingCodeTests {
    @Test("Generates 6-digit numeric codes")
    internal func testCodeGeneration() {
      for _ in 0..<20 {
        let code = RappPairingCode.generate()
        #expect(code.count == 6)
        #expect(RappPairingCode.isValid(code))
        #expect(RappPairingCode.normalize(code) == code)
      }
    }

    @Test("Normalizes and formats numeric codes")
    internal func testNormalizationAndFormatting() {
      let raw = "123-456"
      let normalized = RappPairingCode.normalize(raw)
      #expect(normalized == "123456")
      #expect(RappPairingCode.isValid(normalized))
      #expect(RappPairingCode.formatted("123456") == "123 456")
      #expect(RappPairingCode.formatted("123") == "123 ")
      #expect(RappPairingCode.formatted("1234") == "123 4")

      #expect(!RappPairingCode.isValid("123"))
      #expect(!RappPairingCode.isValid("12345678"))
    }

    @Test("Deterministically derives identical pairing secrets and offer URIs")
    internal func testDeterministicDerivation() throws {
      let code1 = "123456"
      let code2 = "123456"

      let secret1 = RappPairingCode.pairingSecret(for: code1)
      let secret2 = RappPairingCode.pairingSecret(for: code2)
      #expect(secret1 == secret2)
      #expect(secret1.count == 32)

      let offerId1 = RappPairingCode.offerIdentifier(for: code1)
      let offerId2 = RappPairingCode.offerIdentifier(for: code2)
      #expect(offerId1 == offerId2)
      #expect(offerId1.count == 32)

      let candidate = RappTransportCandidate(
        profile: rappStreamProfileName(),
        candidateId: "stream-1",
        parametersCbor: Data([0b1010_0000])
      )
      let (_, uri1) = try RappPairingCode.pairingOffer(for: code1, candidate: candidate)
      let (_, uri2) = try RappPairingCode.pairingOffer(for: code2, candidate: candidate)
      #expect(uri1 == uri2)
    }

    @Test(
      "Completes end-to-end pairing ceremony between Requester and Proxy using 6-digit code")
    internal func testPairingCeremonyWithSixDigitCode() async throws {
      let code = "123456"
      let candidateID = "apple-peer-v1.nearby"
      let profiles = [
        "fi.refineid.card-status.v1",
        "fi.refineid.authentication.v1",
        "fi.refineid.document-signing.v1",
      ]
      let (requester, proxy) = try await makeConnectedPair(
        code: code,
        candidateID: candidateID,
        profiles: profiles
      )

      async let requesterPairTask = approveAndAwaitPair(requester, profiles: profiles)
      async let proxyPairTask = approveAndAwaitPair(proxy, profiles: profiles)

      await proxy.transportConnected()
      await requester.transportConnected()

      let requesterSummary = try await requesterPairTask
      let proxySummary = try await proxyPairTask

      #expect(requesterSummary.role == .requester)
      #expect(proxySummary.role == .proxy)
      #expect(requesterSummary.pairID == proxySummary.pairID)
    }

    private func makeConnectedPair(
      code: String,
      candidateID: String,
      profiles: [String]
    ) async throws -> (RappPairingCoordinator, RappPairingCoordinator) {
      let candidate = RappPairingCoordinator.TransportCandidate(
        profile: "apple-peer-v1",
        candidateID: candidateID,
        parametersCBOR: Data([0xA0])
      )
      let testID = UUID().uuidString
      let requesterVault = RappDeviceVault(
        accessGroup: nil,
        servicePrefix: "fi.refineid.tests.pairing.\(testID).requester"
      )
      let proxyVault = RappDeviceVault(
        accessGroup: nil,
        servicePrefix: "fi.refineid.tests.pairing.\(testID).proxy"
      )
      let requesterOutbound = SignRelayFrameEndpoint()
      let proxyOutbound = SignRelayFrameEndpoint()

      let requester = try RappPairingCoordinator.requester(
        profiles: profiles,
        candidates: [candidate],
        selectedCandidateID: candidateID,
        offerLifetimeMilliseconds: 60_000,
        displayName: "iPad Requester",
        platform: "iOS",
        vault: requesterVault,
        transport: RappClosureFrameTransport(
          sender: { frame in await requesterOutbound.send(frame) },
          closer: { await requesterOutbound.close() }
        ),
        code: code
      )
      let proxy = try RappPairingCoordinator.proxy(
        scannedOfferURI: try #require(requester.offerURI),
        selectedCandidateID: candidateID,
        displayName: "iPhone Proxy",
        platform: "iOS",
        vault: proxyVault,
        transport: RappClosureFrameTransport(
          sender: { frame in await proxyOutbound.send(frame) },
          closer: { await proxyOutbound.close() }
        ),
        code: code
      )
      await requesterOutbound.install { frame in await proxy.receive(frame) }
      await proxyOutbound.install { frame in await requester.receive(frame) }
      return (requester, proxy)
    }

    private func approveAndAwaitPair(
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
          throw SignRelayPairingFailure.closed("\(reason)")

        case .offerReady, .offerRestored:
          continue
        }
      }
      throw SignRelayPairingFailure.endedWithoutRecord
    }
  }
#endif
