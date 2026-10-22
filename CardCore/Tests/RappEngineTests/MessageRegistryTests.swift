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
      ["granted_profiles": .array([.text("fi.refineid.authentication")])]

    case .pairingAbort:
      ["reason": .text("declined")]

    case .pairingStored:
      ["pair_id": .bytes(operation)]

    case .cardStatus:
      ["card_present": .boolean(true), "certificate_fingerprint": .bytes(digest)]

    case .sessionReady:
      ["parameters": .map([:]), "nonce": .bytes(digest)]

    case .sessionClose:
      ["reason": .text("user_disconnect")]

    case .livenessPing, .livenessPong:
      ["challenge": .bytes(digest)]

    default:
      [:]
    }
  }

  private static func operationBody(for messageType: MessageType) -> [String: WireValue] {
    switch messageType {
    case .operationRequest:
      [
        "operation_id": .bytes(operation), "profile": .text("fi.refineid.authentication"),
        "action": .text("browser_authenticate"),
        "expires_after_ms": .unsigned(expiryMilliseconds), "context": .map([:]),
        "payload": .map([:]),
      ]

    case .operationProgress:
      ["operation_id": .bytes(operation), "event": .text("waiting_for_card")]

    case .operationResult:
      ["operation_id": .bytes(operation), "status": .text("completed"), "response": .map([:])]

    default:
      ["error_name": .text("busy"), "message": .text("Another operation is live.")]
    }
  }
  @Test("Every registered message type survives a round trip")
  internal func registryRoundTrip() throws {
    for messageType in MessageType.allCases {
      let envelope = Envelope(
        messageType: messageType, sessionIdentifier: Self.session, sequence: Self.sequence,
        body: Self.body(for: messageType))
      let decoded = try Envelope.decode(try envelope.encoded())
      #expect(decoded == envelope, "\(messageType.rawValue)")
    }
  }

  @Test("A body the registry does not admit is refused")
  internal func registryRefusals() {
    var missingAction = Self.body(for: .operationRequest)
    missingAction["action"] = nil
    expectRefusal(missingAction, .operationRequest, "MissingField { field: \"action\" }")

    var hashOnRequest = Self.body(for: .operationRequest)
    hashOnRequest["request_hash"] = .bytes(Self.digest)
    expectRefusal(hashOnRequest, .operationRequest, "UnknownField")

    var unregisteredErrorName = Self.body(for: .error)
    unregisteredErrorName["error_name"] = .text("unknown_operation")
    expectRefusal(unregisteredErrorName, .error, "InvalidValue { field: \"error_name\" }")

    var sequencedClose = Self.body(for: .sessionClose)
    sequencedClose["last_received_sequence"] = .unsigned(Self.sequence)
    expectRefusal(sequencedClose, .sessionClose, "UnknownField")

    var shortFingerprint = Self.body(for: .cardStatus)
    shortFingerprint["certificate_fingerprint"] = .bytes(Data(count: Self.shortIdentifierSize))
    expectRefusal(
      shortFingerprint, .cardStatus, "WrongType { field: \"certificate_fingerprint\" }")

    var emptyErrorName = Self.body(for: .error)
    emptyErrorName["error_name"] = .text("")
    expectRefusal(emptyErrorName, .error, "InvalidValue { field: \"error_name\" }")

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
    badStatus["status"] = .text("ambiguous")
    expectRefusal(badStatus, .operationResult, "InvalidValue { field: \"status\" }")

    var retiredReason = Self.body(for: .sessionClose)
    retiredReason["reason"] = .text("credential_rejected")
    expectRefusal(retiredReason, .sessionClose, "InvalidValue { field: \"reason\" }")
  }

  private func expectRefusal(
    _ body: [String: WireValue],
    _ messageType: MessageType,
    _ expected: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let envelope = Envelope(
      messageType: messageType, sessionIdentifier: Self.session, sequence: 0, body: body)
    let actual = CorpusFailure.name { _ = try Envelope.decode(try envelope.encoded()) }
    #expect(actual == expected, sourceLocation: sourceLocation)
  }
}
