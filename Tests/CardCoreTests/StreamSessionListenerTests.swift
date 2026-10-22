// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Network
import Testing

@testable import CardCore

/// The custodian's session listener carries any number of connections at
/// once, each apart, and an open one is never a reason to refuse another
/// (RAPP v26.10.22 §2.2.2); a dialer that never presents a frame is closed.
@Suite(.serialized)
internal struct StreamSessionListenerTests {
  /// What the listener reported, by connection.
  private actor Heard {
    private(set) var connected: [StreamSessionConnection] = []
    private(set) var frames: [StreamSessionConnection: [Data]] = [:]
    private(set) var closed: [StreamSessionConnection] = []

    func record(_ event: StreamSessionListener.Event) {
      switch event {
      case .connected(let connection):
        connected.append(connection)

      case .frame(let connection, let frame):
        frames[connection, default: []].append(frame)

      case .closed(let connection, _):
        closed.append(connection)

      case .ended:
        break
      }
    }

    /// The connection whose first frame was `frame`.
    func connection(sending frame: Data) -> StreamSessionConnection? {
      frames.first { $0.value.first == frame }?.key
    }
  }

  private static let attempts = 100
  private static let pause = Duration.milliseconds(50)
  private static let macPreamble = Data("mac session preamble".utf8)
  private static let laptopPreamble = Data("laptop session preamble".utf8)
  private static let answer = Data("answer for one connection".utf8)
  private static let shortFirstFrameTimeoutMilliseconds = 300

  /// The listener's port once it is ready to accept.
  private static func boundPort(of listener: StreamSessionListener) async throws -> UInt16 {
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

  /// Dials the listener on loopback, presenting `preamble` first.
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

  @Test
  internal func twoDialersHoldTwoConnectionsAtOnce() async throws {
    let heard = Heard()
    let listener = StreamSessionListener { event in Task { await heard.record(event) } }
    listener.start(displayName: StreamRendezvousName.ephemeralName(), txtRecord: [:])
    defer { listener.cancel() }
    let port = try await Self.boundPort(of: listener)

    let macHeard = StreamRelayMailbox()
    let mac = Self.dial(port: port, preamble: Self.macPreamble, into: macHeard)
    defer { mac.cancel() }
    let laptopHeard = StreamRelayMailbox()
    let laptop = Self.dial(port: port, preamble: Self.laptopPreamble, into: laptopHeard)
    defer { laptop.cancel() }

    #expect(
      try await Self.waitUntil {
        let fromMac = await heard.connection(sending: Self.macPreamble)
        let fromLaptop = await heard.connection(sending: Self.laptopPreamble)
        return fromMac != nil && fromLaptop != nil
      })
    let macConnection = try #require(await heard.connection(sending: Self.macPreamble))
    let laptopConnection = try #require(await heard.connection(sending: Self.laptopPreamble))
    #expect(macConnection != laptopConnection)

    // An answer on one connection reaches only its own dialer.
    try listener.send(Self.answer, on: laptopConnection)
    #expect(try await Self.waitUntil { await laptopHeard.firstFrame == Self.answer })
    #expect(await macHeard.firstFrame == nil)

    // Closing one connection leaves the other open.
    listener.disconnect(macConnection)
    #expect(try await Self.waitUntil { await macHeard.reported.contains("closed") })
    #expect(await heard.closed == [macConnection])
    try listener.send(Self.answer, on: laptopConnection)
    #expect(try await Self.waitUntil { await laptopHeard.reported.contains("frame") })
    #expect(await laptopHeard.reported.contains("closed") == false)
  }

  @Test
  internal func aDialerThatSendsNothingIsClosed() async throws {
    let heard = Heard()
    let listener = StreamSessionListener(
      firstFrameTimeout: .milliseconds(Self.shortFirstFrameTimeoutMilliseconds)
    ) { event in Task { await heard.record(event) } }
    listener.start(displayName: StreamRendezvousName.ephemeralName(), txtRecord: [:])
    defer { listener.cancel() }
    let port = try await Self.boundPort(of: listener)
    let silent = NWConnection(
      host: .ipv4(.loopback), port: try #require(NWEndpoint.Port(rawValue: port)), using: .tcp)
    silent.start(queue: .global())
    defer { silent.cancel() }
    #expect(try await Self.waitUntil { await heard.connected.count == 1 })
    #expect(try await Self.waitUntil { await heard.closed.count == 1 })
  }
}
