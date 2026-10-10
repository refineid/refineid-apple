// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Network
import RappEngine
import Testing

@testable import CardCore

/// A requester finds a session-mode holder by its rotating hint alone and
/// opens with fresh routing the holder resolves to its pairing (RAPP
/// v26.10.10 §2.2.1 and the discovery hierarchy §4.3).
@Suite(.serialized)
internal struct StreamSessionLoopbackTests {
  private static let attempts = 100
  private static let pause = Duration.milliseconds(100)

  private static func pairing() throws -> (custodian: RappPairRecord, requester: RappPairRecord) {
    let custodianKey = Curve25519.KeyAgreement.PrivateKey()
    let requesterKey = Curve25519.KeyAgreement.PrivateKey()
    return (
      try RappSameAccountPairBuilder.makePairRecord(
        localStaticPrivate: custodianKey.rawRepresentation,
        localStaticPublic: custodianKey.publicKey.rawRepresentation,
        localRole: .proxy,
        remotePublicKey: requesterKey.publicKey.rawRepresentation),
      try RappSameAccountPairBuilder.makePairRecord(
        localStaticPrivate: requesterKey.rawRepresentation,
        localStaticPublic: requesterKey.publicKey.rawRepresentation,
        localRole: .requester,
        remotePublicKey: custodianKey.publicKey.rawRepresentation)
    )
  }

  @Test
  internal func aRequesterFindsItsHolderByHintAndPresentsItsPreamble() async throws {
    let pair = try Self.pairing()
    let profile = rappStreamProfileName()
    let preamble = try pair.requester.sessionPreamble(transportProfile: profile)
    let hint = try pair.custodian.discoveryHint(
      unixTimeSeconds: StreamRendezvousName.unixTime(Date()))
    let name = StreamRendezvousName.ephemeralName()

    let heard = StreamRelayMailbox()
    let listener = StreamRelayListener { event in
      Task { await heard.record(event) }
    }
    listener.start(
      displayName: name,
      txtRecord: StreamRendezvousName.sessionRecord(
        candidates: [RappAnnouncementCandidate(hint: hint, lastUsedMs: 0)]))
    defer { listener.cancel() }

    let found = StreamRelayEndpointBox()
    let browser = StreamRelayBrowser(
      matchingRecord: { record in
        StreamRendezvousName.sessionRecord(record, holds: pair.requester, at: Date())
      },
      onFound: { endpoint in
        Task { await found.set(endpoint) }
      })
    browser.start()
    defer { browser.cancel() }

    var endpoint: NWEndpoint?
    for _ in 0..<Self.attempts where endpoint == nil {
      endpoint = await found.matching(name)
      if endpoint == nil { try await Task.sleep(for: Self.pause) }
    }
    let service = try #require(endpoint, "the browser never found the session listener")

    let dialer = StreamRelaySession(service: service, preamble: preamble) { _ in
      // this probe only dials; it does not handle frames
    }
    dialer.start()
    defer { dialer.cancel() }

    var arrived: Data?
    for _ in 0..<Self.attempts where arrived == nil {
      arrived = await heard.firstFrame
      if arrived == nil { try await Task.sleep(for: Self.pause) }
    }
    #expect(arrived == preamble)
    let routed = RappSessionRouter().route(
      transportProfile: profile, preamble: try #require(arrived), records: [pair.custodian])
    #expect(routed == .session(index: 0))
  }
}
