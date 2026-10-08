// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  @Suite("RAPP 6-character Crockford Base32 pairing code and ceremony")
  internal struct RappPairingCodeTests {
    @Test("Generates 6-character Crockford Base32 codes")
    internal func testCodeGeneration() {
      for _ in 0..<50 {
        let code = RappPairingCode.generate()
        #expect(code.count == RappPairingCode.codeLength)
        #expect(RappPairingCode.isValid(code))
        #expect(RappPairingCode.normalize(code) == code)
        // Excluded visually ambiguous symbols per RAPP v26.10.1 §3.1
        #expect(!code.contains("I"))
        #expect(!code.contains("L"))
        #expect(!code.contains("O"))
        #expect(!code.contains("U"))
      }
    }

    @Test("Normalizes and formats Crockford Base32 codes into 2-character clusters")
    internal func testNormalizationAndFormatting() {
      let raw = "7k-x4-m9"
      let normalized = RappPairingCode.normalize(raw)
      #expect(normalized == "7KX4M9")
      #expect(RappPairingCode.isValid(normalized))
      #expect(RappPairingCode.formatted(normalized) == "7K X4 M9")
      #expect(RappPairingCode.formatted("7K") == "7K")
      #expect(RappPairingCode.formatted("7KX") == "7K X")
      #expect(RappPairingCode.formatted("7KX4") == "7K X4")

      #expect(!RappPairingCode.isValid("7KX4"))
      #expect(!RappPairingCode.isValid("7KX4M9AB"))
    }

    @Test("Normalizes compatibility forms first and uppercases only ASCII")
    internal func testCompatibilityAndAsciiCase() {
      #expect(RappPairingCode.normalize("\u{FF17}k\tx4\u{00A0}m9") == "7KX4M9")
      #expect(RappPairingCode.normalize("7KX4M\u{00DF}").isEmpty)
      #expect(RappPairingCode.normalize("7KX4M9AB") == "7KX4M9AB")
      #expect(!RappPairingCode.isValid("7KX4M9AB"))
    }

    @Test("Applies Crockford decode aliases (I, L -> 1; O -> 0)")
    internal func testCrockfordDecodeAliases() {
      #expect(RappPairingCode.normalize("iLo8k2") == "1108K2")
      #expect(RappPairingCode.normalize("ILO8K2") == "1108K2")
      #expect(RappPairingCode.isValid("1108K2"))
    }

    @Test("Rejects invalid characters and U")
    internal func testRejectsInvalidCharacters() {
      // U is explicitly rejected per RAPP v26.10.1 §3.1
      #expect(RappPairingCode.normalize("7KU4M9").isEmpty)
      #expect(!RappPairingCode.isValid("7KU4M9"))

      // Non-Crockford symbols
      #expect(RappPairingCode.normalize("7K#4M9").isEmpty)
      #expect(!RappPairingCode.isValid("7K#4M9"))
      #expect(!RappPairingCode.isValid(""))
    }

    @Test("Deterministically derives identical pairing secrets and offer URIs")
    internal func testDeterministicDerivation() throws {
      let code1 = "7KX4M9"
      let code2 = "7KX4M9"

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
      "Completes end-to-end pairing ceremony between Requester and Proxy using Crockford code")
    internal func testPairingCeremonyWithSixDigitCode() async throws {
      let code = "7KX4M9"
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
