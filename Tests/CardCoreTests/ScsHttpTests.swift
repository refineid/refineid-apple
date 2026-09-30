// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// The one-request-per-connection HTTP framing this implementation
/// uses for the SCS exchange.
@Suite
internal struct ScsHttpTests {
  @Test
  internal func assemblesAConcatenatedRequest() {
    let wire =
      "POST /sign HTTP/1.1\r\nOrigin: https://dvv.fineid.fi\r\n"
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
  internal func refusesANegativeContentLength() {
    // A declared negative length passed every guard and handed a negative
    // count to the body assembly, which traps; it must be invalid instead.
    let wire = "POST /sign HTTP/1.1\r\nContent-Length: -1\r\n\r\n"
    #expect(ScsHttpAssembly.assemble(buffer: Data(wire.utf8)) == .invalid)
  }

  @Test
  internal func refusesAnUnparseableContentLength() {
    // Garbage or an overflowing number must not fall back to a valid
    // empty body.
    let overflow = "POST /sign HTTP/1.1\r\nContent-Length: 18446744073709551616\r\n\r\n"
    #expect(ScsHttpAssembly.assemble(buffer: Data(overflow.utf8)) == .invalid)
    let garbage = "POST /sign HTTP/1.1\r\nContent-Length: many\r\n\r\n"
    #expect(ScsHttpAssembly.assemble(buffer: Data(garbage.utf8)) == .invalid)
  }

  @Test
  internal func waitsForTheWholeBody() {
    let wire = "POST /sign HTTP/1.1\r\nContent-Length: 10\r\n\r\nhalf"
    #expect(ScsHttpAssembly.assemble(buffer: Data(wire.utf8)) == .needMoreData)
  }

  @Test
  internal func waitsForTheHeadBoundary() {
    #expect(
      ScsHttpAssembly.assemble(buffer: Data("GET /version HTTP/1.1\r\n".utf8))
        == .needMoreData)
  }

  @Test
  internal func stripsTheQueryString() {
    let wire = "GET /version?probe=1 HTTP/1.1\r\n\r\n"
    let assembly = ScsHttpAssembly.assemble(buffer: Data(wire.utf8))
    guard case .complete(let exchange) = assembly else {
      Issue.record("expected a complete request")
      return
    }
    #expect(exchange.request.path == "/version")
  }

  @Test
  internal func responsesEchoTheOriginAndClose() throws {
    let response = ScsHttpResponse.json(
      status: 200,
      body: Data("{}".utf8),
      origin: "https://dvv.fineid.fi"
    )
    let text = try #require(String(data: response, encoding: .utf8))
    #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
    #expect(text.contains("Access-Control-Allow-Origin: https://dvv.fineid.fi\r\n"))
    #expect(text.contains("Connection: close\r\n"))
    #expect(text.contains("Content-Length: 2\r\n"))
    #expect(text.hasSuffix("\r\n\r\n{}"))
  }

  @Test
  internal func preflightAnswersOkWithCors() throws {
    let response = ScsHttpResponse.preflight(origin: "https://dvv.fineid.fi")
    let text = try #require(String(data: response, encoding: .utf8))
    #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
    #expect(text.contains("Access-Control-Allow-Methods: GET, POST\r\n"))
  }
}
