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

      async let requesterPairTask = awaitPair(requester)
      async let proxyPairTask = awaitPair(proxy)

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

      func options(
        _ name: String, vault: RappDeviceVault, outbound: SignRelayFrameEndpoint
      ) -> RappPairingCoordinator.Options {
        RappPairingCoordinator.Options(
          code: code,
          profiles: profiles,
          candidate: candidate,
          displayName: name,
          platform: "iOS",
          vault: vault,
          transport: RappClosureFrameTransport(
            sender: { frame in await outbound.send(frame) },
            closer: { await outbound.close() }
          )
        )
      }
      let requester = try RappPairingCoordinator.requester(
        options: options("iPad Requester", vault: requesterVault, outbound: requesterOutbound))
      let proxy = try RappPairingCoordinator.custodian(
        options: options("iPhone Proxy", vault: proxyVault, outbound: proxyOutbound))
      await requesterOutbound.install { frame in await proxy.receive(frame) }
      await proxyOutbound.install { frame in await requester.receive(frame) }
      return (requester, proxy)
    }

    private func awaitPair(
      _ coordinator: RappPairingCoordinator
    ) async throws -> RappPairingCoordinator.PairSummary {
      for await event in coordinator.events {
        switch event {
        case .paired(let summary):
          return summary

        case .closed(let reason):
          throw SignRelayPairingFailure.closed("\(reason)")

        case .peerIntroduced, .offerRestored:
          continue
        }
      }
      throw SignRelayPairingFailure.endedWithoutRecord
    }
  }
#endif
