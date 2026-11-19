// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Network
import Testing

/// Drives `StreamRelaySession` against a localhost `NWListener` double,
/// proving the length-prefixed framing, preamble-first ordering, EOF
/// handling, and generation guarding of the stream transport.
@Suite(.serialized)
internal final class StreamRelaySessionTests {
  private static let eventTimeout: TimeInterval = 10
  private static let quietWindowMilliseconds = 300
  private static let preamble = Data("test-stream-preamble".utf8)
  private static let applicationFrame = Data("test-application-frame".utf8)

  /// Binds a loopback listener to learn a free port, then closes it so
  /// dialing that port is refused.
  private static func vacatedLoopbackPort() async throws -> UInt16 {
    let queue = DispatchQueue(label: "fi.refineid.tests.vacated-port")
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
      host: .ipv4(.loopback),
      port: .any
    )
    let listener = try NWListener(using: parameters)
    listener.newConnectionHandler = { connection in
      connection.cancel()
    }
    let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
          listener.stateUpdateHandler = nil
          continuation.resume(returning: listener.port?.rawValue ?? 0)

        case .failed(let error):
          listener.stateUpdateHandler = nil
          continuation.resume(throwing: error)

        case .setup, .waiting, .cancelled:
          break

        @unknown default:
          break
        }
      }
      listener.start(queue: queue)
    }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      listener.stateUpdateHandler = { state in
        guard case .cancelled = state else { return }
        listener.stateUpdateHandler = nil
        continuation.resume()
      }
      listener.cancel()
    }
    return port
  }

  @Test
  internal func testPreambleFirstThenEchoedFrames() async throws {
    let listenerFrames = RecordedLog<Data>()
    let events = RecordedLog<StreamRelayEvent>()
    let preambleSeen = TestEvent(description: "listener read the preamble first")
    let applicationFrameSeen = TestEvent(description: "listener read the sent frame")
    let connected = TestEvent(description: "session reported connected")
    let echoReceived = TestEvent(description: "session received the echoed frame")

    let listener = try LoopbackStreamListener(script: .echoFramesAfterFirst) { frame in
      let count = listenerFrames.append(frame)
      if count == 1 { preambleSeen.signal() }
      if count == 2 { applicationFrameSeen.signal() }
    }
    defer { listener.stop() }
    let port = try await listener.start()

    let session = StreamRelaySession(
      endpointLiterals: ["127.0.0.1:\(port)"],
      preamble: Self.preamble
    ) { event in
      events.append(event)
      switch event {
      case .connected:
        connected.signal()

      case .frame:
        echoReceived.signal()

      case .closed:
        break
      }
    }
    defer { session.cancel() }
    session.start()

    await TestEvent.wait(for: [connected, preambleSeen], timeout: Self.eventTimeout)
    try await session.send(Self.applicationFrame)
    await TestEvent.wait(
      for: [applicationFrameSeen, echoReceived],
      timeout: Self.eventTimeout
    )

    #expect((listenerFrames.values) == ([Self.preamble, Self.applicationFrame]))
    let receivedFrames: [Data] = events.values.compactMap { event in
      guard case .frame(let payload) = event else { return nil }
      return payload
    }
    #expect((receivedFrames) == ([Self.applicationFrame]))

  }

  @Test
  internal func testListenerCloseReportsDisconnected() async throws {
    let listenerFrames = RecordedLog<Data>()
    let events = RecordedLog<StreamRelayEvent>()
    let closed = TestEvent(description: "session reported closed")

    let listener = try LoopbackStreamListener(script: .closeAfterFirstFrame) { frame in
      listenerFrames.append(frame)
    }
    defer { listener.stop() }
    let port = try await listener.start()
    let session = StreamRelaySession(
      endpointLiterals: ["127.0.0.1:\(port)"],
      preamble: Self.preamble
    ) { event in
      events.append(event)
      guard case .closed = event else { return }
      closed.signal()
    }
    defer { session.cancel() }
    session.start()

    await TestEvent.wait(for: [closed], timeout: Self.eventTimeout)
    guard case .closed(let error)? = events.values.last else {
      Issue.record("Expected a closed event")
      return
    }
    #expect((error) == (.disconnected))
  }

  @Test
  internal func testZeroLengthPrefixReportsMalformedFrame() async throws {
    let listenerFrames = RecordedLog<Data>()
    let events = RecordedLog<StreamRelayEvent>()
    let closed = TestEvent(description: "session reported closed")

    let listener = try LoopbackStreamListener(
      script: .zeroLengthPrefixAfterFirstFrame
    ) { frame in
      listenerFrames.append(frame)
    }
    defer { listener.stop() }
    let port = try await listener.start()
    let session = StreamRelaySession(
      endpointLiterals: ["127.0.0.1:\(port)"],
      preamble: Self.preamble
    ) { event in
      events.append(event)
      guard case .closed = event else { return }
      closed.signal()
    }
    defer { session.cancel() }
    session.start()

    await TestEvent.wait(for: [closed], timeout: Self.eventTimeout)
    guard case .closed(let error)? = events.values.last else {
      Issue.record("Expected a closed event")
      return
    }
    #expect((error) == (.malformedFrame))
  }

  @Test
  internal func testDialsEndpointsInOrderPastDeadEndpoint() async throws {
    let listenerFrames = RecordedLog<Data>()
    let preambleSeen = TestEvent(description: "listener read the preamble")
    let connected = TestEvent(description: "session reported connected")

    let deadPort = try await Self.vacatedLoopbackPort()
    let listener = try LoopbackStreamListener(script: .echoFramesAfterFirst) { frame in
      let count = listenerFrames.append(frame)
      if count == 1 { preambleSeen.signal() }
    }
    let livePort = try await listener.start()

    let session = StreamRelaySession(
      endpointLiterals: [
        "not-an-endpoint",
        "127.0.0.1:\(deadPort)",
        "127.0.0.1:\(livePort)",
      ],
      preamble: Self.preamble
    ) { event in
      guard case .connected = event else { return }
      connected.signal()
    }
    defer { session.cancel() }
    session.start()

    await TestEvent.wait(for: [connected, preambleSeen], timeout: Self.eventTimeout)
    #expect((listenerFrames.values) == ([Self.preamble]))
  }

  @Test
  internal func testExhaustedEndpointsReportUnreachable() async throws {
    let events = RecordedLog<StreamRelayEvent>()
    let closed = TestEvent(description: "session reported closed")

    let deadPort = try await Self.vacatedLoopbackPort()
    let session = StreamRelaySession(
      endpointLiterals: ["not-an-endpoint", "127.0.0.1:\(deadPort)"],
      preamble: Self.preamble
    ) { event in
      events.append(event)
      guard case .closed = event else { return }
      closed.signal()
    }
    defer { session.cancel() }
    session.start()

    await TestEvent.wait(for: [closed], timeout: Self.eventTimeout)
    guard case .closed(let error)? = events.values.last else {
      Issue.record("Expected a closed event")
      return
    }
    #expect((error) == (.unreachable))
  }

  @Test
  internal func testCancelReportsClosedOnceAndDropsLaterFrames() async throws {
    let listenerFrames = RecordedLog<Data>()
    let events = RecordedLog<StreamRelayEvent>()
    let connected = TestEvent(description: "session reported connected")
    let closed = TestEvent(description: "session reported closed")

    let listener = try LoopbackStreamListener(script: .echoFramesAfterFirst) { frame in
      listenerFrames.append(frame)
    }
    defer { listener.stop() }
    let port = try await listener.start()
    let session = StreamRelaySession(
      endpointLiterals: ["127.0.0.1:\(port)"],
      preamble: Self.preamble
    ) { event in
      events.append(event)
      switch event {
      case .connected:
        connected.signal()

      case .closed:
        closed.signal()

      case .frame:
        break
      }
    }
    var didCancel = false
    defer {
      if !didCancel { session.cancel() }
    }
    session.start()
    await TestEvent.wait(for: [connected], timeout: Self.eventTimeout)

    session.cancel()
    didCancel = true
    await TestEvent.wait(for: [closed], timeout: Self.eventTimeout)
    let countAtClose = events.values.count
    guard case .closed(let error)? = events.values.last else {
      Issue.record("Expected a closed event")
      return
    }
    #expect((error) == (.cancelled))

    listener.sendFrameToPeer(Self.applicationFrame)
    try await Task.sleep(for: .milliseconds(Self.quietWindowMilliseconds))
    #expect((events.values.count) == (countAtClose))
    let closedEventCount = events.values.count { event in
      guard case .closed = event else { return false }
      return true
    }
    #expect((closedEventCount) == (1))
  }
}
