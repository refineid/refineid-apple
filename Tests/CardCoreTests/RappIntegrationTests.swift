// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine
  @Suite
  internal struct RappIntegrationTests {

    // MARK: Functions

    @Test
    internal func closureTransportPreservesFramesAndClosesExactlyOnce() async throws {
      let recorder = RappIntegrationFixtures.TransportRecorder()
      let transport = RappClosureFrameTransport(
        sender: { frame in await recorder.record(frame) },
        closer: { await recorder.close() }
      )
      let frame = Data([0x01, 0x02, 0x03])

      try await transport.send(frame)
      await transport.close()
      await transport.close()

      let snapshot = await recorder.snapshot()
      #expect(snapshot.frames == [frame])
      #expect(snapshot.closeCount == 1)

      do {
        try await transport.send(Data([0x04]))
        Issue.record("A closed RAPP transport accepted another frame")
      } catch is CancellationError {
        // Expected: a closed transport cannot silently reopen.
      } catch {
        Issue.record("A closed RAPP transport returned the wrong error")
      }
    }

    @Test
    internal func cardOperationMappingsAreCompleteAndRoundTrip() throws {
      let keyProfiles: [CardKeyProfile] = [
        .ecdsaP256,
        .ecdsaP384,
        .rsa2048,
        .rsa3072,
      ]
      for keyProfile in keyProfiles {
        #expect(RappOperationDriver.KeyProfile(keyProfile).cardKeyProfile == keyProfile)
      }

      let algorithms = [
        SigningAlgorithm(hash: .sha224, scheme: .ecdsa),
        SigningAlgorithm(hash: .sha256, scheme: .ecdsa),
        SigningAlgorithm(hash: .sha384, scheme: .ecdsa),
        SigningAlgorithm(hash: .sha512, scheme: .ecdsa),
        SigningAlgorithm(hash: .sha256, scheme: .rsaPkcs1),
        SigningAlgorithm(hash: .sha384, scheme: .rsaPkcs1),
        SigningAlgorithm(hash: .sha512, scheme: .rsaPkcs1),
        SigningAlgorithm(hash: .sha256, scheme: .rsaPss),
      ]
      for algorithm in algorithms {
        let mapped = try #require(RappOperationDriver.SignatureAlgorithm(algorithm))
        #expect(mapped.signingAlgorithm.hash == algorithm.hash)
        #expect(mapped.signingAlgorithm.scheme == algorithm.scheme)
      }

      #expect(
        RappOperationDriver.SignatureAlgorithm(
          SigningAlgorithm(hash: .sha224, scheme: .rsaPkcs1)
        ) == nil)
      #expect(
        RappOperationDriver.SignatureAlgorithm(
          SigningAlgorithm(hash: .sha384, scheme: .rsaPss)
        ) == nil)
    }

    @Test
    internal func swiftCoordinatorsPairThroughRustAndRevocationRemovesThePair() async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }

      #expect(fixture.requesterSummary.pairID == fixture.proxySummary.pairID)
      #expect(fixture.requesterSummary.role == .requester)
      #expect(fixture.proxySummary.role == .proxy)
      #expect(Set(fixture.requesterSummary.profiles) == Set(RappIntegrationFixtures.profiles))
      #expect(Set(fixture.proxySummary.profiles) == Set(RappIntegrationFixtures.profiles))
      #expect(fixture.requesterSummary.transportProfile == RappIntegrationFixtures.transportProfile)
      #expect(fixture.requesterSummary.candidateID == RappIntegrationFixtures.candidateID)
      #expect(
        try fixture.requesterVault.loadPair(
          pairID: fixture.requesterSummary.pairID) != nil)
      #expect(try fixture.proxyVault.loadPair(pairID: fixture.proxySummary.pairID) != nil)

      #expect(!fixture.requesterFrames.frames.isEmpty)
      #expect(!fixture.proxyFrames.frames.isEmpty)
      #expect(fixture.requesterFrames.closeCount == 1)
      #expect(fixture.proxyFrames.closeCount == 1)

      let catalog = RappPairCatalog(vault: fixture.requesterVault)
      try await catalog.select(pairID: fixture.requesterSummary.pairID)
      #expect(try await catalog.selectedPair()?.pairID == fixture.requesterSummary.pairID)
      try await catalog.revoke(pairID: fixture.requesterSummary.pairID)
      #expect(
        try fixture.requesterVault.loadPair(
          pairID: fixture.requesterSummary.pairID) == nil)
      #expect(try await catalog.activePairs().isEmpty)
      #expect(try await catalog.selectedPair() == nil)
      #expect(
        try fixture.proxyVault.pairIsRevoked(
          pairID: fixture.proxySummary.pairID) == false)
    }

    /// Neither peer may treat that crossing as a reason to end the pairing:
    /// a holder who presented a card slightly slowly would be told to scan
    /// a fresh code, and the pairing they had would be gone.
    @Test
    internal func aCardCommandOutlastingLivenessKeepsTheSessionAndPairing() async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      let connection = try await RappIntegrationConnectionSupport.makeConnection(
        fixture,
        liveness: RappIntegrationFixtures.interactiveLiveness
      )
      let signature = Data([0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x02])
      let operation = RappIntegrationFixtures.RequestedOperation.browserAuthentication(
        origin: "https://example.invalid",
        digest: Data(repeating: 0xA5, count: 32)
      )

      let requesterOutcome = Task {
        try await RappIntegrationConnectionSupport.awaitCompletion(
          connection.requester, operation: operation)
      }
      let proxyOutcome = Task {
        try await RappIntegrationAuthorizationSupport.authorizeAndComplete(
          connection.proxy,
          operation: operation,
          signature: signature,
          cardHoldMilliseconds: 7_000
        )
      }
      defer {
        requesterOutcome.cancel()
        proxyOutcome.cancel()
      }

      await connection.proxy.start()
      await connection.requester.start()
      let result = try await requesterOutcome.value
      _ = try await proxyOutcome.value

      #expect(result.kind == .signature)
      #expect(result.bytes == signature)
      #expect(
        try fixture.requesterVault.pairIsRevoked(
          pairID: fixture.requesterSummary.pairID) == false)
      #expect(
        try fixture.proxyVault.pairIsRevoked(
          pairID: fixture.proxySummary.pairID) == false)
      await connection.requester.close()
      await connection.proxy.close()
    }

    @Test(arguments: RappIntegrationFixtures.ProxyTermination.allCases)
    internal func nonCredentialTerminalPathsRespectCommandBoundaryAndPreservePairing(
      termination: RappIntegrationFixtures.ProxyTermination
    ) async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      let connection = try await RappIntegrationConnectionSupport.makeConnection(fixture)
      let operation = RappIntegrationFixtures.RequestedOperation.browserAuthentication(
        origin: "https://terminal.example.invalid",
        digest: Data(repeating: UInt8(termination.hashValue & 0xFF), count: 32)
      )

      let requesterOutcome = Task {
        try await RappIntegrationConnectionSupport.awaitTerminal(
          connection.requester, operation: operation)
      }
      let proxyOutcome = Task {
        try await RappIntegrationAuthorizationSupport.authorizeAndTerminate(
          connection.proxy,
          operation: operation,
          termination: termination
        )
      }
      defer {
        requesterOutcome.cancel()
        proxyOutcome.cancel()
      }

      await connection.proxy.start()
      await connection.requester.start()
      let reason = try await requesterOutcome.value
      let progress = try await proxyOutcome.value

      #expect(reason == termination.reason)
      #expect(progress == termination.progress)
      #expect(
        try fixture.requesterVault.pairIsRevoked(
          pairID: fixture.requesterSummary.pairID) == false)
      #expect(
        try fixture.proxyVault.pairIsRevoked(
          pairID: fixture.proxySummary.pairID) == false)
      #expect(
        await connection.proxyOutbound.snapshot().closeCount
          == termination.proxyTransportCloseCount)

      await connection.requester.close()
      await connection.proxy.close()
    }

    @Test
    internal func credentialRejectionRevokesBothPeersWithoutAnotherExecution() async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      let connection = try await RappIntegrationConnectionSupport.makeConnection(fixture)
      let digest = Data(repeating: 0x5A, count: 32)
      let operation = RappIntegrationFixtures.RequestedOperation.browserAuthentication(
        origin: "https://example.invalid",
        digest: digest
      )

      let requesterOutcome = Task {
        try await RappIntegrationConnectionSupport.awaitTerminal(
          connection.requester, operation: operation)
      }
      let proxyOutcome = Task {
        try await RappIntegrationAuthorizationSupport.authorizeAndRejectCredential(
          connection.proxy,
          operation: operation
        )
      }
      defer {
        requesterOutcome.cancel()
        proxyOutcome.cancel()
      }

      await connection.proxy.start()
      await connection.requester.start()
      let reason = try await requesterOutcome.value
      let progress = try await proxyOutcome.value

      await connection.requester.close()
      await connection.proxy.close()

      #expect(reason == .credentialRejected)
      #expect(
        progress
          == RappIntegrationFixtures.ProxyProgress(
            prerequisites: 1,
            approvals: 1,
            executions: 1,
            acknowledgments: 0
          ))
      #expect(
        try fixture.requesterVault.pairIsRevoked(
          pairID: fixture.requesterSummary.pairID) == false)
      #expect(
        try fixture.proxyVault.pairIsRevoked(
          pairID: fixture.proxySummary.pairID) == false)
      #expect(
        try fixture.requesterVault.loadPair(
          pairID: fixture.requesterSummary.pairID) == nil)
      #expect(try fixture.proxyVault.loadPair(pairID: fixture.proxySummary.pairID) == nil)
      #expect(try fixture.requesterVault.activePairIDs().isEmpty)
      #expect(try fixture.proxyVault.activePairIDs().isEmpty)
    }
  }
#endif
