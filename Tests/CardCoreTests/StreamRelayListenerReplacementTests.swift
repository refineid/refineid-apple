// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Network
import Testing

@testable import CardCore

/// A listener with a connection open yields it only to a dialer whose first
/// frame the owner admits; a stranger displaces nothing (RAPP v26.10.18
/// §8.4).
@Suite(.serialized)
internal struct StreamRelayListenerReplacementTests {
  private static let attempts = 100
  private static let pause = Duration.milliseconds(50)
  private static let admitted = Data("admitted-preamble".utf8)
  private static let stranger = Data("stranger-preamble".utf8)

  /// Dials the listener on loopback and keeps what the dial reported.
  private static func dial(
    port: UInt16, preamble: Data, into mailbox: StreamRelayMailbox
  ) -> StreamRelaySession {
    let dialer = StreamRelaySession(endpointLiterals: ["127.0.0.1:\(port)"], preamble: preamble) {
      event in
      Task { await mailbox.record(event) }
    }
    dialer.start()
    return dialer
  }

  /// The listener's port once it is ready to accept.
  private static func boundPort(of listener: StreamRelayListener) async throws -> UInt16 {
    var port: UInt16?
    for _ in 0..<attempts where port == nil {
      if listener.state == "ready" { port = listener.port }
      if port == nil { try await Task.sleep(for: pause) }
    }
    return try #require(port, "the listener never became ready")
  }

  private static func waitUntil(_ condition: @Sendable () async -> Bool) async throws -> Bool {
    for _ in 0..<attempts {
      if await condition() { return true }
      try await Task.sleep(for: pause)
    }
    return await condition()
  }

  @Test
  internal func onlyAnAdmittedFirstFrameDisplacesTheOpenConnection() async throws {
    let heard = StreamRelayMailbox()
    let listener = StreamRelayListener(
      admitsReplacement: { $0 == Self.admitted },
      onEvent: { event in Task { await heard.record(event) } })
    listener.start(displayName: StreamRendezvousName.ephemeralName())
    defer { listener.cancel() }
    let bound = try await Self.boundPort(of: listener)

    let firstHeard = StreamRelayMailbox()
    let first = Self.dial(port: bound, preamble: Self.admitted, into: firstHeard)
    defer { first.cancel() }
    #expect(try await Self.waitUntil { await heard.firstFrame == Self.admitted })
    #expect(await heard.reported == "connected, frame(\(Self.admitted.count))")

    // A stranger is dropped and the first connection stays.
    let strangerHeard = StreamRelayMailbox()
    let strangerDial = Self.dial(port: bound, preamble: Self.stranger, into: strangerHeard)
    defer { strangerDial.cancel() }
    #expect(try await Self.waitUntil { await strangerHeard.reported.contains("closed") })
    #expect(await heard.reported == "connected, frame(\(Self.admitted.count))")
    #expect(await firstHeard.reported.contains("closed") == false)

    // An admitted dialer takes the connection's place, its frame first.
    let secondHeard = StreamRelayMailbox()
    let second = Self.dial(port: bound, preamble: Self.admitted, into: secondHeard)
    defer { second.cancel() }
    #expect(try await Self.waitUntil { await firstHeard.reported.contains("closed") })
    // The mailbox records on its own tasks, so only the set of events is
    // compared: the first connection closed once, the admitted dialer
    // was connected, and both admitted frames arrived.
    let replaced = [
      "connected", "frame(\(Self.admitted.count))", "closed(disconnected)", "connected",
      "frame(\(Self.admitted.count))",
    ].sorted()
    #expect(
      try await Self.waitUntil {
        await heard.reported.components(separatedBy: ", ").sorted() == replaced
      })
    let reported = await heard.reported
    #expect(reported.components(separatedBy: ", ").sorted() == replaced, "\(reported)")
  }

  @Test
  internal func withoutAnAdmissionPolicyASecondDialerIsRefused() async throws {
    let heard = StreamRelayMailbox()
    let listener = StreamRelayListener { event in Task { await heard.record(event) } }
    listener.start(displayName: StreamRendezvousName.ephemeralName())
    defer { listener.cancel() }
    let bound = try await Self.boundPort(of: listener)
    let first = Self.dial(port: bound, preamble: Self.admitted, into: StreamRelayMailbox())
    defer { first.cancel() }
    #expect(try await Self.waitUntil { await heard.firstFrame == Self.admitted })
    let secondHeard = StreamRelayMailbox()
    let second = Self.dial(port: bound, preamble: Self.admitted, into: secondHeard)
    defer { second.cancel() }
    #expect(try await Self.waitUntil { await secondHeard.reported.contains("closed") })
    #expect(await heard.reported == "connected, frame(\(Self.admitted.count))")
  }
}
