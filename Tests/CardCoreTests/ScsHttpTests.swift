// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// The one-request-per-connection HTTP framing, loopback `Host`
/// allowlist, 100 MiB body bound, and header-sanitized CORS responses.
@Suite
internal struct ScsHttpTests {
  @Test
  internal func assemblesAConcatenatedRequestWithLoopbackHost() {
    let wire =
      "POST /sign HTTP/1.1\r\nHost: 127.0.0.1:53952\r\nOrigin: https://dvv.fineid.fi\r\n"
      + "Content-Type: application/json\r\nContent-Length: 4\r\n\r\nbody"
    let assembly = ScsHttpAssembly.assemble(buffer: Data(wire.utf8))
    guard case .complete(let exchange) = assembly else {
      Issue.record("expected a complete request")
      return
    }
    #expect(exchange.request.method == "POST")
    #expect(exchange.request.path == "/sign")
    #expect(exchange.request.origin == "https://dvv.fineid.fi")
    #expect(exchange.request.contentType == "application/json")
    #expect(exchange.body == Data("body".utf8))
  }

  @Test
  internal func enforcesLoopbackHostHeaderAllowlist() {
    for validHost in ["127.0.0.1", "127.0.0.1:53952", "localhost", "LOCALHOST:53952"] {
      let wire = "GET /version HTTP/1.1\r\nHost: \(validHost)\r\n\r\n"
      guard case .complete = ScsHttpAssembly.assemble(buffer: Data(wire.utf8)) else {
        Issue.record("expected \(validHost) to be accepted")
        continue
      }
    }
    for rejected in [
      "GET /version HTTP/1.1\r\n\r\n",
      "GET /version HTTP/1.1\r\nHost: evil.example\r\n\r\n",
      "GET /version HTTP/1.1\r\nHost: 127.0.0.1:8080\r\n\r\n",
      "GET /version HTTP/1.1\r\nHost: 127.0.0.1:53952\r\nHost: localhost:53952\r\n\r\n",
    ] {
      #expect(ScsHttpAssembly.assemble(buffer: Data(rejected.utf8)) == .invalid)
    }
  }

  @Test
  internal func refusesInvalidOrSmuggledContentLengthAndTrailingBytes() {
    for rejected in [
      "POST /sign HTTP/1.1\r\nHost: 127.0.0.1:53952\r\nContent-Length: -1\r\n\r\n",
      "POST /sign HTTP/1.1\r\nHost: 127.0.0.1:53952\r\nContent-Length: 18446744073709551616\r\n\r\n",
      "POST /sign HTTP/1.1\r\nHost: 127.0.0.1:53952\r\nContent-Length: many\r\n\r\n",
      "POST /sign HTTP/1.1\r\nHost: 127.0.0.1:53952\r\nTransfer-Encoding: chunked\r\n\r\n",
      "POST /sign HTTP/1.1\r\nHost: 127.0.0.1:53952\r\nContent-Length: 2\r\n\r\nabc",
    ] {
      #expect(ScsHttpAssembly.assemble(buffer: Data(rejected.utf8)) == .invalid)
    }
  }

  @Test
  internal func admitsHundredMegabyteCeilingAndRejectsAboveBeforeBuffering() {
    let atLimit =
      "POST /sign HTTP/1.1\r\nHost: 127.0.0.1:53952\r\nContent-Length: 104857600\r\n\r\n"
    #expect(ScsHttpAssembly.assemble(buffer: Data(atLimit.utf8)) == .needMoreData)

    let overLimit =
      "POST /sign HTTP/1.1\r\nHost: 127.0.0.1:53952\r\nContent-Length: 104857601\r\n\r\n"
    #expect(ScsHttpAssembly.assemble(buffer: Data(overLimit.utf8)) == .invalid)
    #expect(
      !ScsHttpAssembly.exceedsReceiveCeiling(bufferedCount: 65_536, incomingCount: 104_857_600))
    #expect(
      ScsHttpAssembly.exceedsReceiveCeiling(bufferedCount: 65_537, incomingCount: 104_857_600))
  }

  @Test
  internal func waitsForHeadAndBodyAndStripsQueryString() {
    #expect(
      ScsHttpAssembly.assemble(buffer: Data("GET /version HTTP/1.1\r\n".utf8)) == .needMoreData)
    let partial =
      "POST /sign HTTP/1.1\r\nHost: 127.0.0.1:53952\r\nContent-Length: 10\r\n\r\nhalf"
    #expect(ScsHttpAssembly.assemble(buffer: Data(partial.utf8)) == .needMoreData)

    let query = "GET /version?probe=1 HTTP/1.1\r\nHost: localhost:53952\r\n\r\n"
    guard case .complete(let exchange) = ScsHttpAssembly.assemble(buffer: Data(query.utf8)) else {
      Issue.record("expected a complete request")
      return
    }
    #expect(exchange.request.path == "/version")
  }

  @Test
  internal func responsesSanitizeOriginAndBoundPreflightMaxAge() throws {
    let response = ScsHttpResponse.json(
      status: 200,
      body: Data("{}".utf8),
      origin: "https://dvv.fineid.fi"
    )
    let text = try #require(String(data: response, encoding: .utf8))
    #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
    #expect(text.contains("Access-Control-Allow-Origin: https://dvv.fineid.fi\r\n"))
    #expect(text.contains("Access-Control-Max-Age: 600\r\n"))
    #expect(text.contains("Connection: close\r\n"))
    #expect(text.hasSuffix("\r\n\r\n{}"))

    let injected = ScsHttpResponse.preflight(
      origin: "https://evil.example\r\nX-Injected: yes"
    )
    let injectedText = try #require(String(data: injected, encoding: .utf8))
    #expect(!injectedText.contains("X-Injected"))
    #expect(injectedText.contains("Access-Control-Allow-Origin: null\r\n"))
  }
}
