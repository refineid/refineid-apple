// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
// https://www.apache.org/licenses/LICENSE-2.0

#if DEBUG && os(macOS)
  import Foundation
  import os
  import Testing

  @testable import RefineIDTestHost

  @Suite(.serialized, DssGateFixtureScope())
  internal struct DssGateFixtureLifetimeTests {
    private enum Expected: Error, Equatable { case fixtureBodyFinished }

    private static let syntheticRacePayload = Data("synthetic".utf8)
    private static let raceHeadStartSeconds = 60

    private static func isSynthetic(_ configuration: URLSessionConfiguration) -> Bool {
      configuration.protocolClasses?.contains { protocolClass in
        ObjectIdentifier(protocolClass) == ObjectIdentifier(DssGateUrlProtocol.self)
      } ?? false
    }

    @Test
    internal func thrownBodyClearsTheFixtureBeforeReturning() async throws {
      let authorities = try DssGateAuthorities.make()
      await #expect(throws: Expected.fixtureBodyFinished) {
        try await DssGateSessionHook.withFixture(authorities: authorities) {
          #expect(DssGateSessionHook.isFixtureActive)
          #expect(Self.isSynthetic(URLSessionConfiguration.ephemeral))
          throw Expected.fixtureBodyFinished
        }
      }
      let authoritiesCleared = DssGateUrlProtocol.authorities == nil
      let timestampAuthoritiesCleared = DssGateUrlProtocol.timestampAuthorities == nil
      #expect(authoritiesCleared)
      #expect(timestampAuthoritiesCleared)
      #expect(!DssGateSessionHook.isFixtureActive)
      #expect(!Self.isSynthetic(URLSessionConfiguration.ephemeral))
    }

    @Test
    internal func unrelatedTaskKeepsItsNativeSessionConfiguration() async throws {
      let authorities = try DssGateAuthorities.make()
      try await DssGateSessionHook.withFixture(authorities: authorities) {
        #expect(Self.isSynthetic(URLSessionConfiguration.ephemeral))
        let unrelatedWasSynthetic = await Task.detached {
          Self.isSynthetic(URLSessionConfiguration.ephemeral)
        }.value
        #expect(!unrelatedWasSynthetic)
        #expect(Self.isSynthetic(URLSessionConfiguration.ephemeral))
      }
    }

    @Test
    internal func signingNetworkRacePropagatesFixtureToBothStructuredChildren() async throws {
      let authorities = try DssGateAuthorities.make()
      let observed = OSAllocatedUnfairLock<(validated: Bool, plain: Bool)>(
        initialState: (validated: false, plain: false)
      )
      try await DssGateSessionHook.withFixture(authorities: authorities) {
        let answer = try await SigningNetwork.firstAnswer(
          headStart: .seconds(Self.raceHeadStartSeconds),
          validated: {
            let synthetic = Self.isSynthetic(
              SigningNetwork.validatedSessionConfiguration(validating: true)
            )
            observed.withLock { $0.validated = synthetic }
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
          },
          plain: {
            let synthetic = Self.isSynthetic(
              SigningNetwork.validatedSessionConfiguration(validating: false)
            )
            observed.withLock { $0.plain = synthetic }
            return Self.syntheticRacePayload
          }
        )
        #expect(answer.outcome == .plain)
        #expect(answer.data == Self.syntheticRacePayload)
      }
      let results = observed.withLock { $0 }
      #expect(results.validated)
      #expect(results.plain)
    }
  }
#endif
