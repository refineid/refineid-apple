// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  /// The slim relay over a real pairing and a real handshake: a requester
  /// asks a proxy to sign, and the answer comes back.
  @Suite
  internal struct SignRelayEndToEndTests {
    // MARK: Static Properties

    private static let profiles = [
      "fi.refineid.card-status.v1",
      "fi.refineid.authentication.v1",
      "fi.refineid.document-signing.v1",
    ]
    private static let transportProfile = "apple-peer-v1"
    private static let signature = Data([0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x02])

    // MARK: Functions

    /// One request crosses a session established over a stored pairing.
    @Test
    internal func aRequestCrossesAnEstablishedSession() async throws {
      let paired = try await SignRelayPairing.make(
        profiles: Self.profiles,
        transportProfile: Self.transportProfile
      )
      defer { paired.deleteKeychainServices() }

      let requesterSession = try SignRelaySession(
        role: .requester,
        pair: try RappPairRecord.loadFromVault(
          pairId: paired.requesterPairID, vault: paired.requesterVault),
        vault: paired.requesterVault
      )
      let proxySession = try SignRelaySession(
        role: .proxy,
        pair: try RappPairRecord.loadFromVault(
          pairId: paired.proxyPairID, vault: paired.proxyVault),
        vault: paired.proxyVault
      )

      let wire = SignRelayWire(requester: requesterSession, proxy: proxySession)
      await wire.answerWith { request in
        .signatureResponse(requestID: request.requestID, signature: Self.signature)
      }
      try await wire.establish()

      #expect(await requesterSession.isEstablished)
      #expect(await proxySession.isEstablished)

      let requestID = UUID()
      let answer = try await wire.ask(
        .signatureRequest(
          requestID: requestID,
          profile: .ecdsaP256,
          algorithm: .ecdsaSHA256,
          digest: Data(repeating: 0xA5, count: 32)
        ))

      #expect(answer == .signatureResponse(requestID: requestID, signature: Self.signature))
    }
  }
#endif
