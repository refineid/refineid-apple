// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Synchronization
import Testing

@Suite("CryptoTokenKit signature continuation")
internal struct SmartCardTransmitTests {
  private enum TransportFailure: Error {
    case disconnected
  }

  private static let protectedRsa = Data([
    0x0C, 0x2A, 0x9E, 0x9A, 0x0D,
    0x97, 0x01, 0x00, 0x8E, 0x08, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x00,
  ])
  private static let rsaSignatureBytes = 384

  @Test("A modulus-wide signature completes through one structured operation")
  internal func rsaContinuationIsOwnedByCtk() throws {
    let body = Data(repeating: 0xA5, count: Self.rsaSignatureBytes)
    let returned = Mutex<Data?>(nil)
    var sends = 0
    SmartCardTransmit.start(
      Self.protectedRsa,
      transmit: { _, _ in
        Issue.record("Raw signature transmission exposes a separate GET RESPONSE")
      },
      send: { command, completion in
        sends += 1
        #expect(command == CommandApdu.structuredProtectedSignature(Self.protectedRsa))
        completion(body, StatusWord.success.encoded, nil)
      },
      reply: { response, error in
        #expect(error == nil)
        returned.withLock { $0 = response }
      })
    #expect(sends == 1)
    let response = try #require(returned.withLock { $0 })
    #expect(response.dropLast(2) == body)
    #expect(response.suffix(2) == Data([0x90, 0x00]))
  }

  @Test(
    "PACE and exact-length signatures preserve byte-exact transmission",
    arguments: [
      Data([0x10, 0x86, 0x00, 0x00, 0x02, 0x7C, 0x00, 0x00]),
      Data([
        0x0C, 0x2A, 0x9E, 0x9A, 0x0D,
        0x97, 0x01, 0x60, 0x8E, 0x08, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x60,
      ]),
    ])
  internal func otherCommandsStayRaw(payload: Data) {
    let expected = Data([0x90, 0x00])
    let returned = Mutex<Data?>(nil)
    SmartCardTransmit.start(
      payload,
      transmit: { command, completion in
        #expect(command == payload)
        completion(expected, nil)
      },
      send: { _, _ in Issue.record("This command must not use CTK continuation") },
      reply: { response, error in
        #expect(error == nil)
        returned.withLock { $0 = response }
      })
    #expect(returned.withLock { $0 } == expected)
  }

  @Test("Structured transport loss stays a failure without a fabricated response")
  internal func failedContinuationDoesNotBecomeSuccess() {
    let completed = Mutex(false)
    SmartCardTransmit.start(
      Self.protectedRsa,
      transmit: { _, _ in Issue.record("Unexpected raw transmission") },
      send: { _, completion in
        completion(nil, StatusWord.success.encoded, TransportFailure.disconnected)
      },
      reply: { response, error in
        completed.withLock { $0 = true }
        #expect(response == nil)
        #expect(error is TransportFailure)
      })
    #expect(completed.withLock { $0 })
  }
}
