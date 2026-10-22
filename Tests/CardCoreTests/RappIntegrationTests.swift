// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security
import Testing

@testable import CardCore

#if canImport(RappEngine)
  @testable import RappEngine
  @Suite
  internal struct RappIntegrationTests {
    // MARK: Static Properties

    /// How long the card command holds the custodian: past the silence
    /// after which a ping goes out (RAPP v26.10.22 §8.3), plus two liveness
    /// polls so the exchange has happened before the answer leaves.
    private static let cardHoldPastPing = Duration.milliseconds(
      LivenessTracker.pingAfterSilenceMilliseconds
        + RappConnectionCoordinator.livenessPollIntervalMilliseconds
        + RappConnectionCoordinator.livenessPollIntervalMilliseconds)

    /// What the requester sends on a session without liveness: the opening
    /// handshake message and one operation request.
    private static let requesterFramesWithoutLiveness = 2

    // MARK: Functions

    @Test
    internal func closureTransportPreservesFramesAndClosesExactlyOnce() async throws {
      let recorder = RappIntegrationFixtures.TransportRecorder()
      let transport = RappClosureFrameTransport(
        sender: { frame in await recorder.record(frame) },
        closer: { await recorder.close() }
      )
      let frame = Data("first frame".utf8)

      try await transport.send(frame)
      await transport.close()
      await transport.close()

      let snapshot = await recorder.snapshot()
      #expect(snapshot.frames == [frame])
      #expect(snapshot.closeCount == 1)

      do {
        try await transport.send(Data("after close".utf8))
        Issue.record("A closed RAPP transport accepted another frame")
      } catch is CancellationError {
        // Expected: a closed transport cannot silently reopen.
      } catch {
        Issue.record("A closed RAPP transport returned the wrong error")
      }
    }

    @Test
    internal func cardOperationMappingsAreCompleteAndRoundTrip() throws {
      let keyProfiles: [CardCore.CardKeyProfile] = [
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
    internal func coordinatorsPairAndRevocationRemovesThePair() async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }

      #expect(fixture.requesterSummary.pairID == fixture.proxySummary.pairID)
      #expect(fixture.requesterSummary.role == .requester)
      #expect(fixture.proxySummary.role == .proxy)
      #expect(Set(fixture.requesterSummary.profiles) == Set(RappIntegrationFixtures.profiles))
      #expect(Set(fixture.proxySummary.profiles) == Set(RappIntegrationFixtures.profiles))
      #expect(fixture.requesterSummary.transportProfile == RappIntegrationFixtures.transportProfile)
      #expect(
        fixture.requesterSummary.candidateID
          == rappCandidateIdentifier(transportProfile: RappIntegrationFixtures.transportProfile))
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

    /// A card command that outlasts the silence after which a ping goes out
    /// keeps the session and the pairing: liveness is answered while the
    /// custodian waits on the card.
    @Test
    internal func aCardCommandOutlastingLivenessKeepsTheSessionAndPairing() async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      let connection = try await RappIntegrationConnectionSupport.makeConnection(fixture)
      let operation = RappIntegrationFixtures.RequestedOperation.browserAuthentication(
        origin: "https://example.invalid")

      let requesterOutcome = Task {
        try await RappIntegrationConnectionSupport.awaitCompletion(
          connection.requester, operation: operation)
      }
      let proxyOutcome = Task {
        try await RappIntegrationAuthorizationSupport.authorizeAndComplete(
          connection.proxy,
          operation: operation,
          signature: RappIntegrationFixtures.signature,
          cardHold: Self.cardHoldPastPing
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

      #expect(result == .signature(RappIntegrationFixtures.signature))
      #expect(
        await connection.requesterOutbound.snapshot().frames.count
          > Self.requesterFramesWithoutLiveness,
        "no liveness message crossed the card command")
      #expect(
        try fixture.requesterVault.pairIsRevoked(
          pairID: fixture.requesterSummary.pairID) == false)
      #expect(
        try fixture.proxyVault.pairIsRevoked(
          pairID: fixture.proxySummary.pairID) == false)
      await connection.requester.close()
      await connection.proxy.close()
    }

    /// Every failure the custodian reports reaches the requester as its
    /// registered error, keeps both pairings, and leaves the session
    /// serving the next operation.
    @Test(arguments: RappIntegrationFixtures.ProxyTermination.allCases)
    internal func terminalPathsKeepTheSessionAndPairing(
      termination: RappIntegrationFixtures.ProxyTermination
    ) async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      let connection = try await RappIntegrationConnectionSupport.makeConnection(fixture)
      let operation = RappIntegrationFixtures.RequestedOperation.browserAuthentication(
        origin: termination.origin)

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
      #expect(await connection.proxyOutbound.snapshot().closeCount == 0)

      let next = RappIntegrationFixtures.RequestedOperation.browserAuthentication(
        origin: "https://next.example.invalid")
      let nextProxy = Task {
        try await RappIntegrationAuthorizationSupport.authorizeAndComplete(
          connection.proxy, operation: next, signature: RappIntegrationFixtures.signature)
      }
      defer { nextProxy.cancel() }
      let result = try await RappIntegrationConnectionSupport.complete(
        next, on: connection.requester)
      _ = try await nextProxy.value
      #expect(result == .signature(RappIntegrationFixtures.signature))

      #expect(
        try fixture.requesterVault.pairIsRevoked(
          pairID: fixture.requesterSummary.pairID) == false)
      #expect(
        try fixture.proxyVault.pairIsRevoked(
          pairID: fixture.proxySummary.pairID) == false)
      #expect(try fixture.requesterVault.loadPair(pairID: fixture.requesterSummary.pairID) != nil)
      #expect(try fixture.proxyVault.loadPair(pairID: fixture.proxySummary.pairID) != nil)

      await connection.requester.close()
      await connection.proxy.close()
    }

    /// The custodian's word on its card and its reader reaches the
    /// requester as it was said: which card is present, a reader attached
    /// beside it, and then neither (§8.4).
    @Test
    internal func cardStatusCarriesTheFingerprintTheReaderAndTheirAbsence() async throws {
      let fixture = try await RappIntegrationConnectionSupport.makePairedFixture()
      defer { RappIntegrationConnectionSupport.deleteKeychainServices(for: fixture) }
      let connection = try await RappIntegrationConnectionSupport.makeConnection(fixture)
      let fingerprint = try #require(RappIntegrationFixtures.cardFingerprint)
      let reported = [
        RappCardStatus(card: .present(fingerprint), reader: .absent),
        RappCardStatus(card: .present(fingerprint), reader: .attached),
        RappCardStatus(card: .absent, reader: .attached),
        RappCardStatus(card: .absent, reader: .absent),
      ]

      let requesterHeard = Task {
        try await RappIntegrationConnectionSupport.awaitCardStatuses(
          connection.requester, count: reported.count)
      }
      defer { requesterHeard.cancel() }

      await connection.proxy.start()
      await connection.requester.start()
      try await RappIntegrationConnectionSupport.awaitEstablished(connection.proxy)
      for status in reported {
        try await connection.proxy.reportCardStatus(status)
      }

      #expect(try await requesterHeard.value == reported)
      await connection.requester.close()
      await connection.proxy.close()
    }
  }
#endif
