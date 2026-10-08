// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Network
import RappEngine
import Security
import Testing

@testable import CardCore

/// A requester finds a session-mode holder by its rotating hint alone and
/// opens with its pairing's preamble (RAPP discovery hierarchy §4.3).
@Suite(.serialized)
internal struct StreamSessionLoopbackTests {
  private static let attempts = 100
  private static let pause = Duration.milliseconds(100)
  private static let tokenByteCount = 16

  private static func freshToken() -> Data {
    var bytes = [UInt8](repeating: 0, count: tokenByteCount)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    precondition(status == errSecSuccess, "The system random source failed")
    return Data(bytes)
  }

  @Test
  internal func aRequesterFindsItsHolderByHintAndPresentsItsPreamble() async throws {
    let token = Self.freshToken()
    let preamble = try rappStreamSessionPreamble(rendezvousToken: token)
    let name = StreamRendezvousName.ephemeralName()

    let heard = StreamRelayMailbox()
    let listener = StreamRelayListener { event in
      Task { await heard.record(event) }
    }
    listener.start(
      displayName: name,
      txtRecord: StreamRendezvousName.sessionRecord(rendezvousTokens: [token], at: Date()))
    defer { listener.cancel() }

    let found = StreamRelayEndpointBox()
    let browser = StreamRelayBrowser(
      matchingRecord: { record in
        StreamRendezvousName.sessionRecord(record, mayHold: token, at: Date())
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
  }
}
