// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Network
import Testing

@testable import CardCore

/// The transport that replaces peer discovery with a published service and
/// a dialled port.
@Suite(.serialized)
internal struct StreamRelayLoopbackTests {
  // MARK: Static Properties

  private static let attempts = 100
  private static let pause = Duration.milliseconds(100)

  // MARK: Static Functions

  private static func awaitFrame(in mailbox: StreamRelayMailbox) async throws -> Data {
    for _ in 0..<attempts {
      if let frame = await mailbox.firstFrame { return frame }
      try await Task.sleep(for: pause)
    }
    throw StreamRelayTestFailure.noFrame
  }

  // MARK: Functions

  /// A dialer finds the listener by browsing and carries a frame to it.
  ///
  /// This is the pair the devices use: the requester publishes and the
  /// holder finds it, with no peer framework between them.
  @Test
  internal func aBrowserFindsTheListenerAndTheDialerReachesIt() async throws {
    let name = "RefineID test \(UUID().uuidString.prefix(6))"
    let greeting = Data("found you".utf8)

    let heard = StreamRelayMailbox()
    let listener = StreamRelayListener { event in
      Task { await heard.record(event) }
    }
    listener.start(displayName: name)
    defer { listener.cancel() }

    let found = StreamRelayEndpointBox()
    let browser = StreamRelayBrowser(matching: name) { endpoint in
      Task { await found.set(endpoint) }
    }
    browser.start()
    defer { browser.cancel() }

    var endpoint: NWEndpoint?
    for _ in 0..<Self.attempts where endpoint == nil {
      endpoint = await found.matching(name)
      if endpoint == nil { try await Task.sleep(for: Self.pause) }
    }
    let service = try #require(endpoint, "the browser never found the listener")

    let dialer = StreamRelaySession(service: service, preamble: greeting) { _ in
      // this probe only dials; it does not handle frames
    }
    dialer.start()
    defer { dialer.cancel() }

    let arrived = try? await Self.awaitFrame(in: heard)
    let saw = await heard.reported
    #expect(arrived == greeting, "listener saw: \(saw)")
  }

  /// A dialer reaches a listener and each carries a frame to the other.
  ///
  /// This is the whole of what the nearby transport stopped doing between
  /// two devices: accept a connection and carry bytes both ways.
  @Test
  internal func aDialerReachesAListenerAndBothCarryFrames() async throws {
    let fromDialer = Data("to the holder".utf8)
    let fromListener = Data("to the requester".utf8)

    let heard = StreamRelayMailbox()
    let listener = StreamRelayListener { event in
      Task { await heard.record(event) }
    }
    listener.start(displayName: "RefineID test \(UUID().uuidString.prefix(6))")
    defer { listener.cancel() }

    // A listener reports port zero until it is actually listening, and a
    // zero port is not an address a dialer can parse.
    var bound: UInt16?
    for _ in 0..<Self.attempts where bound == nil {
      let reported = listener.port
      if let reported, reported != 0 {
        bound = reported
      } else {
        try await Task.sleep(for: Self.pause)
      }
    }
    let port = try #require(bound, "the listener never bound a usable port")

    let dialed = StreamRelayMailbox()
    let dialer = StreamRelaySession(
      endpointLiterals: ["[::1]:\(port)", "127.0.0.1:\(port)"],
      preamble: fromDialer
    ) { event in
      Task { await dialed.record(event) }
    }
    dialer.start()
    defer { dialer.cancel() }

    let arrived = try? await Self.awaitFrame(in: heard)
    let listenerSaw = await heard.reported
    let dialerSaw = await dialed.reported
    let comment: Comment = """
      listener state: \(listener.state); \
      listener saw: \(listenerSaw); dialer saw: \(dialerSaw)
      """
    #expect(arrived == fromDialer, comment)

    try listener.send(fromListener)
    let answered = try? await Self.awaitFrame(in: dialed)
    let dialerFinally = await dialed.reported
    #expect(answered == fromListener, "dialer saw: \(dialerFinally)")
  }

  /// Presence reports a find and then a loss when the listener stops.
  @Test
  internal func presenceReportsFindThenLoss() async throws {
    let name = "RefineID test \(UUID().uuidString.prefix(6))"
    let box = StreamRelayPresenceBox()
    let listener = StreamRelayListener { _ in
      // presence only watches the name; it does not take a dial
    }
    listener.start(displayName: name)
    defer { listener.cancel() }

    let presence = StreamRelayPresence(matching: name) { present in
      Task { await box.add(present) }
    }
    presence.start()
    defer { presence.cancel() }

    var sawPresent = false
    for _ in 0..<Self.attempts where !sawPresent {
      sawPresent = await box.contains(true)
      if !sawPresent { try await Task.sleep(for: Self.pause) }
    }
    #expect(sawPresent, "presence never saw the listener")

    listener.cancel()

    var sawAbsent = false
    for _ in 0..<Self.attempts where !sawAbsent {
      sawAbsent = await box.sawTrueThenFalse
      if !sawAbsent { try await Task.sleep(for: Self.pause) }
    }
    #expect(sawAbsent, "presence never saw the listener leave")
  }

  /// An empty name never matches any advertiser.
  @Test
  internal func emptyNamePresenceNeverMatches() async throws {
    let name = "RefineID test \(UUID().uuidString.prefix(6))"
    let box = StreamRelayPresenceBox()
    let listener = StreamRelayListener { _ in
      // presence probe only
    }
    listener.start(displayName: name)
    defer { listener.cancel() }

    let presence = StreamRelayPresence(matching: "") { present in
      Task { await box.add(present) }
    }
    presence.start()
    defer { presence.cancel() }

    try await Task.sleep(for: Duration.milliseconds(500))
    let sawPresent = await box.contains(true)
    #expect(!sawPresent, "presence with empty name matched an advertiser")
  }
}
