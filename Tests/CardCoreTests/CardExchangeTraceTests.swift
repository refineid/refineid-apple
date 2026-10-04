// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

@Suite
internal struct CardExchangeTraceTests {
  // MARK: Static Properties

  /// A SELECT command APDU: CLA INS P1 P2 Lc, with a two-byte body.
  private static let selectRequest = Data([0x00, 0xA4, 0x04, 0x0C, 0x02, 0x3F, 0x00])

  /// A VERIFY command APDU carrying a padded PIN block.
  private static let verifyRequest = Data([
    0x00, 0x20, 0x00, 0x81, 0x08, 0x31, 0x32, 0x33, 0x34, 0xFF, 0xFF, 0xFF, 0xFF,
  ])

  private static let currentPinDigits = "1234"
  private static let replacementPinDigits = "5678"
  private static let pukDigits = "12345678"

  // MARK: Static Functions

  /// Production construction of CHANGE REFERENCE DATA for PIN 1.
  private static func changeReferenceDataRequest() -> Data {
    guard
      let current = Pin1(digits: Self.currentPinDigits),
      let replacement = Pin1(digits: Self.replacementPinDigits)
    else {
      fatalError("test PINs must satisfy production validation")
    }
    let command = CredentialBearingCommand.changePin1(
      current: current.consumeForSingleTransmission(),
      new: replacement.consumeForSingleTransmission(),
      references: .citizen
    )
    return command.intoTransportPayload()
  }

  /// Production construction of RESET RETRY COUNTER for PIN 1.
  private static func resetRetryCounterRequest() -> Data {
    guard
      let puk = Puk(digits: Self.pukDigits),
      let replacement = Pin1(digits: Self.replacementPinDigits)
    else {
      fatalError("test PUK and PIN must satisfy production validation")
    }
    let command = CredentialBearingCommand.unblockPin1(
      puk: puk.consumeForSingleTransmission(),
      new: replacement.consumeForSingleTransmission(),
      references: .citizen
    )
    return command.intoTransportPayload()
  }

  // MARK: Functions

  @Test
  internal func namesInstructionSizesAndStatus() {
    let line = CardExchangeTrace.line(
      request: Self.selectRequest,
      response: Data([0x6F, 0x01, 0x90, 0x00]),
      elapsed: .milliseconds(12))
    #expect(line.contains("ins=A4"))
    #expect(line.contains("tx=7"))
    #expect(line.contains("rx=2"))
    #expect(line.contains("sw=9000"))
    #expect(line.contains("ms=12.0"))
  }

  @Test("Assembled RSA responses report status and size without exposing payload")
  internal func assembledResponseMetadata() {
    let signatureBytes = 384
    var response = Data(repeating: 0xA5, count: signatureBytes)
    response.append(contentsOf: [0x90, 0x00])
    let line = CardExchangeTrace.line(
      request: Self.selectRequest, response: response, elapsed: .milliseconds(12))
    #expect(line.contains("rx=384"))
    #expect(line.contains("sw=9000"))
    #expect(!line.contains("A5A5"))
  }

  @Test
  internal func verifyExchangeOmitsCredentialBytesAndLength() {
    let line = CardExchangeTrace.line(
      request: Self.verifyRequest,
      response: Data([0x63, 0xC4]),
      elapsed: .milliseconds(8))
    #expect(line.contains("ins=20"))
    #expect(line.contains("sw=63C4"))
    #expect(line.contains("redacted"))
    #expect(!line.contains("tx=13"))
    #expect(!line.contains("request="))
    #expect(!line.contains("response="))
  }

  @Test
  internal func credentialMutationsOmitBytesAndLengths() {
    let requests = [
      Self.changeReferenceDataRequest(),
      Self.resetRetryCounterRequest(),
    ]
    for request in requests {
      let line = CardExchangeTrace.line(
        request: request,
        response: Data([0x63, 0xC4]),
        elapsed: .milliseconds(9))
      #expect(line.contains("sw=63C4"))
      #expect(line.contains("credential"))
      #expect(line.contains("redacted"))
      #expect(!line.contains("tx=\(request.count)"))
      #expect(!line.contains("request="))
      #expect(!line.contains("response="))
    }
  }

  @Test
  internal func survivesAnAnswerlessExchange() {
    let line = CardExchangeTrace.line(
      request: Self.selectRequest,
      response: nil,
      elapsed: .seconds(1))
    #expect(line.contains("sw=?"))
    #expect(line.contains("ms=1000.0"))
  }

  @Test
  internal func survivesATruncatedRequest() {
    let line = CardExchangeTrace.line(
      request: Data([0x00]),
      response: Data([0x90, 0x00]),
      elapsed: .zero)
    #expect(line.contains("ins=?"))
    #expect(line.contains("sw=9000"))
    #expect(!line.contains("request="))
    #expect(!line.contains("response="))
  }
}
