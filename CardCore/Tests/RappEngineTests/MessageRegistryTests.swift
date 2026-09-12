// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
//
// The corpus exercises only one message type, so the registry is covered here:
// every registered type must encode, decode and validate, and the schema must
// bite when a body is wrong. These expectations are this repository's own.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP message registry")
internal struct MessageRegistryTests {
  private static let identifierSize = 16
  private static let digestSize = 32
  private static let shortIdentifierSize = 15
  private static let sequence: UInt64 = 7
  private static let expiryMilliseconds: UInt64 = 120_000

  private static let session = Data(repeating: 0xA1, count: WireLimits.sessionIdentifier)
  private static let operation = Data(repeating: 0xB2, count: identifierSize)
  private static let digest = Data(repeating: 0xC3, count: digestSize)

  /// A minimal valid body for each registered message type.
  private static func body(for messageType: MessageType) -> [String: WireValue] {
    let pairing = pairingBody(for: messageType)
    return pairing.isEmpty ? operationBody(for: messageType) : pairing
  }

  private static func pairingBody(for messageType: MessageType) -> [String: WireValue] {
    switch messageType {
    case .pairingHello:
      ["parameters": .map([:]), "display_name": .text("RefineID"), "platform": .text("iOS")]

    case .pairingConfirm:
      ["granted_profiles": .array([.text("fi.refineid.authentication.v1")])]

    case .pairingAbort:
      ["reason": .text("declined")]

    case .sessionReady:
      ["parameters": .map([:]), "nonce": .bytes(digest)]

    case .sessionClose:
      ["reason": .text("user_disconnect"), "last_received_sequence": .unsigned(sequence)]

    case .livenessPing, .livenessPong:
      ["challenge": .bytes(digest), "last_received_sequence": .unsigned(1)]

    default:
      [:]
    }
  }

  private static func operationBody(for messageType: MessageType) -> [String: WireValue] {
    switch messageType {
    case .operationRequest:
      [
        "operation_id": .bytes(operation), "profile": .text("fi.refineid.authentication.v1"),
        "action": .text("authenticate"), "request_hash": .bytes(digest),
        "expires_after_ms": .unsigned(expiryMilliseconds), "context": .map([:]),
        "payload": .map([:]),
      ]

    case .operationPrepared, .operationCommit, .operationResultAck:
      ["operation_id": .bytes(operation), "request_hash": .bytes(digest)]

    case .operationCancel:
      [
        "operation_id": .bytes(operation), "request_hash": .bytes(digest),
        "reason": .text("holder cancelled"),
      ]

    case .operationResult:
      [
        "operation_id": .bytes(operation), "request_hash": .bytes(digest),
        "status": .text("completed"), "body": .map([:]),
      ]

    case .operationStatusRequest:
      ["operation_id": .bytes(operation)]

    case .operationStatus:
      [
        "operation_id": .bytes(operation), "known": .boolean(true),
        "state": .text("completed"),
      ]

    default:
      ["error": .text("busy")]
    }
  }
  @Test("Every registered message type survives a round trip")
  internal func registryRoundTrip() throws {
    for messageType in MessageType.allCases {
      let envelope = Envelope(
        messageType: messageType, sessionIdentifier: Self.session, sequence: Self.sequence,
        body: Self.body(for: messageType), critical: [], extensions: [:])
      let decoded = try Envelope.decode(try envelope.encoded())
      #expect(decoded == envelope, "\(messageType.rawValue)")
    }
  }

  @Test("A body the registry does not admit is refused")
  internal func registryRefusals() {
    var missingHash = Self.body(for: .operationRequest)
    missingHash["request_hash"] = nil
    expectRefusal(
      missingHash, .operationRequest, "MissingField { field: \"request_hash\" }")

    var shortIdentifier = Self.body(for: .operationRequest)
    shortIdentifier["operation_id"] = .bytes(Data(repeating: 0, count: Self.shortIdentifierSize))
    expectRefusal(
      shortIdentifier, .operationRequest, "WrongType { field: \"operation_id\" }")

    var strayField = Self.body(for: .pairingConfirm)
    strayField["unregistered"] = .unsigned(1)
    expectRefusal(strayField, .pairingConfirm, "UnknownField")

    var badReason = Self.body(for: .sessionClose)
    badReason["reason"] = .text("because")
    expectRefusal(badReason, .sessionClose, "InvalidValue { field: \"reason\" }")

    var badStatus = Self.body(for: .operationResult)
    badStatus["status"] = .text("finished")
    expectRefusal(badStatus, .operationResult, "InvalidValue { field: \"status\" }")
  }

  private func expectRefusal(
    _ body: [String: WireValue],
    _ messageType: MessageType,
    _ expected: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let envelope = Envelope(
      messageType: messageType, sessionIdentifier: Self.session, sequence: 0, body: body,
      critical: [], extensions: [:])
    let actual = CorpusFailure.name { _ = try Envelope.decode(try envelope.encoded()) }
    #expect(actual == expected, sourceLocation: sourceLocation)
  }
}
