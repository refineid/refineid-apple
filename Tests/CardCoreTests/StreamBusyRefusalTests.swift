// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Network
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  /// What a phone's stream listener does with connections it answers busy
  /// (RAPP v26.10.29 §4.2, "Busy Refusal").
  @Suite("A stream listener answering busy", .timeLimit(.minutes(1)))
  internal struct StreamBusyRefusalTests {
    // MARK: Static Properties

    private static let typedCode = "246813"
    private static let attempts = 300
    private static let pause = Duration.milliseconds(10)
    /// Leeway under the listener's bound for a closure measured from here.
    private static let leewayMilliseconds: UInt64 = 100
    /// A synthetic frame from a dialer that never reads its answer.
    private static let unreadDialerFrame = Data("first frame".utf8)
    /// A synthetic last frame the listener sends.
    private static let lastFrame = Data("last frame".utf8)
    /// A synthetic busy answer to a second dialer.
    private static let busyFrame = Data("busy".utf8)
    /// When a late second dialer sends its first frame, inside the bound
    /// from accept.
    private static let lateFirstFrame = Duration.milliseconds(1_500)
    /// When it reads its answer, past the bound from accept.
    private static let lateRead = Duration.milliseconds(800)

    // MARK: Static Functions

    private static func port(of listener: StreamRelayListener) async throws -> UInt16 {
      for _ in 0..<attempts {
        if let port = listener.port, port != 0 { return port }
        try await Task.sleep(for: pause)
      }
      throw StreamRelayTestFailure.noFrame
    }

    private static func address(of phone: StreamListeningPhone) async throws -> String {
      for _ in 0..<attempts {
        if let port = await phone.port() { return "127.0.0.1:\(port)" }
        try await Task.sleep(for: pause)
      }
      throw StreamRelayTestFailure.noFrame
    }

    /// The next frame on `events`, skipping the connection report.
    private static func nextFrame(
      _ events: inout AsyncStream<StreamRelayEvent>.Iterator
    ) async throws -> Data {
      while let event = await events.next() {
        if case .frame(let frame) = event { return frame }
        if case .closed = event { break }
      }
      throw StreamRelayTestFailure.noFrame
    }

    /// A raw dialer that sends one frame and never reads or closes.
    private static func unreadDialer(port: UInt16) throws -> NWConnection {
      let connection = NWConnection(
        host: "127.0.0.1", port: try #require(NWEndpoint.Port(rawValue: port)), using: .tcp)
      connection.start(queue: DispatchQueue(label: "fi.refineid.tests.unread-dialer"))
      connection.send(
        content: StreamRelayFraming.encode(unreadDialerFrame),
        completion: .contentProcessed { _ in
          // The listener reports the frame.
        })
      return connection
    }

    // MARK: Functions

    @Test("A refused dialer's close leaves the ceremony serving the first dialer")
    internal func aRefusedDialerLeavesTheFirstServed() async throws {
      let testID = UUID().uuidString
      let vaults = StreamRelayCeremonyVaults(testID: testID)
      defer { vaults.clean() }
      let phone = try StreamListeningPhone(code: Self.typedCode, vault: vaults.proxy)
      await phone.start()
      let address = try await Self.address(of: phone)

      let (served, servedSink) = AsyncStream.makeStream(of: StreamRelayEvent.self)
      let first = StreamRelaySession(
        endpointLiterals: [address], preamble: rappStreamPairingPreamble(),
        onEvent: { servedSink.yield($0) })
      first.start()
      defer { first.cancel() }
      var servedEvents = served.makeAsyncIterator()
      let offer = try await Self.nextFrame(&servedEvents)

      // A second dialer arrives while the first is served, is answered
      // busy, and goes away.
      let second = RappPairingConnection.stream(toAddresses: [address])
      var answer: Data?
      for await event in second.events {
        if case .frame(let frame) = event { answer = frame }
      }
      let busy = try #require(answer)
      #expect(try rappPairingBusyRetryAfterMs(busy) > 0)

      // The first dialer's CPace still runs: T_B verifies.
      let now = RappPlatformClock().monotonicMilliseconds()
      let requester = try RappPairingBridge.bootstrapOffer(
        bootstrap: offer, transportProfile: rappStreamProfileName(),
        pairingCode: Self.typedCode, startedAtMonotonicMs: now)
      try requester.beginCpace(
        candidateId: try #require(
          rappCandidateIdentifier(transportProfile: rappStreamProfileName())),
        randomBytes64: try RappPlatformEntropy().cpaceRandom(), nowMonotonicMs: now)
      try await first.send(try requester.writeCpaceFrame(nowMonotonicMs: now))
      let stepTwo = try await Self.nextFrame(&servedEvents)
      try requester.readCpaceFrame(
        bytes: stepTwo, nowMonotonicMs: RappPlatformClock().monotonicMilliseconds())

      #expect(await phone.reported.isEmpty, "the ceremony saw nothing of the refused dialer")
      #expect(await phone.listenersStarted == 1)
      await phone.stop()
    }

    @Test("A dialer that never reads its last frame is closed after the bound")
    internal func anUnreadLastFrameIsBounded() async throws {
      let (events, sink) = AsyncStream.makeStream(of: StreamRelayEvent.self)
      let listener = StreamRelayListener { sink.yield($0) }
      listener.start(displayName: "RefineID bounded \(UUID().uuidString.prefix(6))")
      defer { listener.cancel() }
      let port = try await Self.port(of: listener)
      var received = events.makeAsyncIterator()

      let silent = try Self.unreadDialer(port: port)
      defer { silent.cancel() }
      #expect(try await Self.nextFrame(&received) == Self.unreadDialerFrame)
      let clock = RappPlatformClock()
      let began = clock.monotonicMilliseconds()
      #expect(listener.endConnection(answering: Self.lastFrame))
      while let event = await received.next() {
        if case .closed = event { break }
      }
      let waited = clock.monotonicMilliseconds() - began
      #expect(
        waited + Self.leewayMilliseconds >= UInt64(StreamRelayListener.endingWaitMilliseconds),
        "closed after the bound, \(waited) ms")

      // The listener is not held: the next dialer is carried.
      let next = try Self.unreadDialer(port: port)
      defer { next.cancel() }
      #expect(try await Self.nextFrame(&received) == Self.unreadDialerFrame)
      #expect(listener.isListening)
    }

    @Test("A second dialer answered late in its window still reads its answer")
    internal func aLateAnswerIsRead() async throws {
      let (events, sink) = AsyncStream.makeStream(of: StreamRelayEvent.self)
      let listener = StreamRelayListener(
        busyAnswer: { _ in Self.busyFrame }, onEvent: { sink.yield($0) })
      listener.start(displayName: "RefineID late \(UUID().uuidString.prefix(6))")
      defer { listener.cancel() }
      let port = try await Self.port(of: listener)
      var received = events.makeAsyncIterator()
      let first = try Self.unreadDialer(port: port)
      defer { first.cancel() }
      #expect(try await Self.nextFrame(&received) == Self.unreadDialerFrame)

      let late = NWConnection(
        host: "127.0.0.1", port: try #require(NWEndpoint.Port(rawValue: port)), using: .tcp)
      late.start(queue: DispatchQueue(label: "fi.refineid.tests.late-dialer"))
      defer { late.cancel() }
      try await Task.sleep(for: Self.lateFirstFrame)
      late.send(
        content: StreamRelayFraming.encode(Self.unreadDialerFrame),
        completion: .contentProcessed { _ in
          // The listener's refusal answers it.
        })
      try await Task.sleep(for: Self.lateRead)
      let answer: Data? = await withCheckedContinuation { continuation in
        late.receive(
          minimumIncompleteLength: 1, maximumLength: StreamRelayFraming.maximumPayloadByteCount
        ) { data, _, _, _ in
          continuation.resume(returning: data)
        }
      }
      var reader = StreamFrameReader()
      #expect(try reader.frames(after: try #require(answer)) == [Self.busyFrame])
    }
  }
#endif
