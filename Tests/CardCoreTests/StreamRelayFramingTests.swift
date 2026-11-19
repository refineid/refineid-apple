// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// Proves the stream endpoint literal grammar, the length-prefixed frame
/// bounds, and the send-side guards that need no live connection.
@Suite(.serialized)
internal final class StreamRelayFramingTests {
  private static let preamble = Data("test-stream-preamble".utf8)
  private static let applicationFrame = Data("test-application-frame".utf8)

  @Test
  internal func testEndpointLiteralParsing() {
    let hostAndPort = StreamRelayEndpoint(literal: "192.0.2.7:4711")
    #expect((hostAndPort?.host) == ("192.0.2.7"))
    #expect((hostAndPort?.port) == (4_711))

    let named = StreamRelayEndpoint(literal: "requester.example:443")
    #expect((named?.host) == ("requester.example"))
    #expect((named?.port) == (443))

    let bracketedIPv6 = StreamRelayEndpoint(literal: "[2001:db8::17]:4711")
    #expect((bracketedIPv6?.host) == ("2001:db8::17"))
    #expect((bracketedIPv6?.port) == (4_711))

    #expect((StreamRelayEndpoint(literal: "no-port")) == nil)
    #expect((StreamRelayEndpoint(literal: ":4711")) == nil)
    #expect((StreamRelayEndpoint(literal: "host:")) == nil)
    #expect((StreamRelayEndpoint(literal: "host:0")) == nil)
    #expect((StreamRelayEndpoint(literal: "host:65536")) == nil)
    #expect((StreamRelayEndpoint(literal: "host:port")) == nil)
    #expect((StreamRelayEndpoint(literal: "2001:db8::17:4711")) == nil)
  }

  @Test
  internal func testFramingBounds() throws {
    let payload = Data("payload".utf8)
    let framed = try #require(StreamRelayFraming.encode(payload))
    #expect((framed.count) == (StreamRelayFraming.lengthPrefixByteCount + payload.count))
    #expect(
      (StreamRelayFraming.payloadByteCount(
        lengthPrefix: framed.prefix(StreamRelayFraming.lengthPrefixByteCount)
      )) == (payload.count))

    let largest = Data(count: StreamRelayFraming.maximumPayloadByteCount)
    #expect((StreamRelayFraming.encode(largest)) != nil)
    let oversized = Data(count: StreamRelayFraming.maximumPayloadByteCount + 1)
    #expect((StreamRelayFraming.encode(oversized)) == nil)
    #expect((StreamRelayFraming.encode(Data())) == nil)

    let zeroLengthPrefix = Data(count: StreamRelayFraming.lengthPrefixByteCount)
    #expect((StreamRelayFraming.payloadByteCount(lengthPrefix: zeroLengthPrefix)) == nil)
    #expect((StreamRelayFraming.payloadByteCount(lengthPrefix: Data())) == nil)
  }

  @Test
  internal func testSendWithoutConnectionThrows() async {
    let events = RecordedLog<StreamRelayEvent>()
    let session = StreamRelaySession(
      endpointLiterals: [],
      preamble: Self.preamble
    ) { event in
      events.append(event)
    }
    do {
      try await session.send(Self.applicationFrame)
      Issue.record("Send without a connection must throw")
    } catch let error as StreamRelayTransportError {
      #expect((error) == (.notConnected))
    } catch {
      Issue.record("Unexpected error type")
    }
  }

  @Test
  internal func testSendRejectsInvalidFrameLengths() async {
    let events = RecordedLog<StreamRelayEvent>()
    let session = StreamRelaySession(
      endpointLiterals: [],
      preamble: Self.preamble
    ) { event in
      events.append(event)
    }
    let oversized = Data(count: StreamRelayFraming.maximumPayloadByteCount + 1)
    for frame in [Data(), oversized] {
      do {
        try await session.send(frame)
        Issue.record("Invalid frame length must throw")
      } catch let error as StreamRelayTransportError {
        #expect((error) == (.invalidFrameLength))
      } catch {
        Issue.record("Unexpected error type")
      }
    }
  }
}
