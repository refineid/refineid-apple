// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Network
import Testing

/// Proves that `StreamRelaySession` dialer lifecycle operations are idempotent
/// and do not generate redundant concurrent connection attempts.
@Suite(.serialized)
internal final class StreamRelayDialerTests {
  private static let eventTimeout: TimeInterval = 10
  private static let quietWindowMilliseconds = 300
  private static let repeatStartAttempts = 5
  private static let singleConnectionCount = 1
  private static let preamble = Data("test-stream-preamble".utf8)

  @Test
  internal func testMultipleStartsAreIdempotentAndDoNotDuplicateConnections() async throws {
    let listenerFrames = RecordedLog<Data>()
    let events = RecordedLog<StreamRelayEvent>()
    let connected = TestEvent(description: "session reported connected")

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
      if case .connected = event {
        connected.signal()
      }
    }
    defer { session.cancel() }

    for _ in 0..<Self.repeatStartAttempts {
      session.start()
    }
    await TestEvent.wait(for: [connected], timeout: Self.eventTimeout)

    try await Task.sleep(for: .milliseconds(Self.quietWindowMilliseconds))
    let connectedCount = events.values.count { event in
      guard case .connected = event else { return false }
      return true
    }
    #expect((connectedCount) == (Self.singleConnectionCount))
    #expect((listenerFrames.values) == ([Self.preamble]))

    session.cancel()
    listener.stop()
  }
}
