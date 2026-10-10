// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  @Suite("RAPP mock test certificate distribution and pairing", .serialized)
  internal struct RappMockCardDistributionTests {
    @Test("Primes synthetic test identity and verifies certificate decoding")
    internal func testSyntheticCertificatePriming() throws {
      PrimeStore.forgetAll()
      let holderName = "DOE JANE 12345678N"
      let can = "123456"
      let tokenSerial = "XA1234567"

      let certDER = try MockCardCertificate.makeCertificate(commonName: holderName)
      guard let cert = SecCertificateCreateWithData(nil, certDER as CFData) else {
        Issue.record("SecCertificateCreateWithData failed to parse synthetic certificate DER")
        return
      }
      let subjectSummary = SecCertificateCopySubjectSummary(cert) as String?
      #expect(subjectSummary == holderName)

      let primed = MockCardCertificate.primeSyntheticIdentity(
        can: can,
        holderName: holderName,
        tokenSerial: tokenSerial,
        certificate: certDER
      )
      #expect(primed)

      let primedCerts = PrimeStore.primedAuthenticationCertificates()
      #expect(!primedCerts.isEmpty)
      #expect(primedCerts.first == certDER)

      let primedHolders = PrimeStore.primedHolderNames()
      #expect(primedHolders.contains("DOE JANE"))
    }

    @Test("Distributes primed test certificate across paired RAPP session")
    internal func testRemoteCertificateDistributionOverRapp() async throws {
      PrimeStore.forgetAll()
      let holderName = "DOE JANE 12345678N"
      let certDER = try MockCardCertificate.makeCertificate(commonName: holderName)
      MockCardCertificate.primeSyntheticIdentity(
        holderName: holderName,
        certificate: certDER
      )

      let code = RappPairingCode.generate()
      let profiles = [
        "fi.refineid.card-status.v1",
        "fi.refineid.authentication.v1",
        "fi.refineid.document-signing.v1",
      ]
      let (requester, proxy) = try await makeConnectedPair(
        code: code,
        profiles: profiles
      )

      async let requesterPairTask = awaitPair(requester)
      async let proxyPairTask = awaitPair(proxy)

      // The requester waits for the offer the custodian serves on connecting.
      await requester.transportConnected()
      await proxy.transportConnected()

      let requesterSummary = try await requesterPairTask
      let proxySummary = try await proxyPairTask

      #expect(requesterSummary.pairID == proxySummary.pairID)

      // Test certificate distribution payload
      let readCertResponse = PrimeStore.primedAuthenticationCertificates().first
      #expect(readCertResponse == certDER)
    }

    private func makeConnectedPair(
      code: String,
      profiles: [String]
    ) async throws -> (RappPairingCoordinator, RappPairingCoordinator) {
      let testID = UUID().uuidString
      let requesterVault = RappDeviceVault(
        accessGroup: nil,
        servicePrefix: "fi.refineid.tests.distrib.\(testID).requester"
      )
      let proxyVault = RappDeviceVault(
        accessGroup: nil,
        servicePrefix: "fi.refineid.tests.distrib.\(testID).proxy"
      )
      let requesterOutbound = SignRelayFrameEndpoint()
      let proxyOutbound = SignRelayFrameEndpoint()

      func options(
        _ name: String, vault: RappDeviceVault, outbound: SignRelayFrameEndpoint
      ) -> RappPairingCoordinator.Options {
        RappPairingCoordinator.Options(
          code: code,
          profiles: profiles,
          transportProfile: "apple-peer-v1",
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
