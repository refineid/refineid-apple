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
    /// The custodian announces the primed card, then answers the read with
    /// its certificate.
    private static func serveCertificate(
      _ certificate: Data,
      as fingerprint: RappCertificateFingerprint,
      on coordinator: RappConnectionCoordinator
    ) async throws {
      for await event in coordinator.events {
        switch event {
        case .established:
          try await coordinator.reportCardStatus(
            RappCardStatus(card: .present(fingerprint), reader: .absent))

        case .inspectPrerequisites(let operationID, _):
          try await coordinator.prerequisitesComplete(operationID: operationID)

        case .executeSafeRead(let operationID, _):
          try await coordinator.completeCertificate(operationID: operationID, der: certificate)
          return

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.connectionClosed(reason)

        default:
          throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    /// Waits for the custodian to name its card, reads that card's
    /// authentication certificate, and answers with both.
    private static func readCertificate(
      _ coordinator: RappConnectionCoordinator
    ) async throws -> (status: RappCardStatus, result: RappOperationResult) {
      var announced: RappCardStatus?
      for await event in coordinator.events {
        switch event {
        case .established, .progress:
          break

        case .cardStatus(let status):
          announced = status
          try await coordinator.beginReadCertificate(
            signatureCertificate: false,
            expiresAfterMilliseconds: RappIntegrationFixtures.FixtureTiming
              .operationExpiryMilliseconds)

        case .completed(_, let result):
          guard let announced else {
            throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
          }
          return (announced, result)

        case .closed(let reason):
          throw RappIntegrationFixtures.TestFailure.connectionClosed(reason)

        default:
          throw RappIntegrationFixtures.TestFailure.unexpectedConnectionEvent
        }
      }
      throw RappIntegrationFixtures.TestFailure.operationEndedWithoutResult
    }

    @Test("Primes synthetic test identity and verifies certificate decoding")
    internal func testSyntheticCertificatePriming() throws {
      PrimeStore.forgetAll()
      let holderName = "DOE JANE 12345678N"
      let can = "123456"
      let chipSerial = try #require(ChipSerial(value: "XA1234567"))

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
        chipSerial: chipSerial,
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
      let primed = try #require(PrimeStore.primedAuthenticationCertificates().first)
      let fingerprint = try #require(RappCertificateFingerprint(certificate: primed))

      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      #expect(fixture.requesterSummary.pairID == fixture.proxySummary.pairID)
      let connection = try await RappIntegrationConnectionSupport.makeConnection(fixture)

      let requesterOutcome = Task { try await Self.readCertificate(connection.requester) }
      let proxyOutcome = Task {
        try await Self.serveCertificate(primed, as: fingerprint, on: connection.proxy)
      }
      defer {
        requesterOutcome.cancel()
        proxyOutcome.cancel()
      }

      await connection.proxy.start()
      await connection.requester.start()
      let received = try await requesterOutcome.value
      try await proxyOutcome.value

      #expect(received.status == RappCardStatus(card: .present(fingerprint), reader: .absent))
      #expect(received.result == .certificate(certDER))
      await connection.requester.close()
      await connection.proxy.close()
    }
  }
#endif
