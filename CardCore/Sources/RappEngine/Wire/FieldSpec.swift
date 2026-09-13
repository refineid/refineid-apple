// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One registered body field: its name, its admitted shape, and whether the
/// registry allows it to be absent.
internal struct FieldSpec {
  internal enum Shape {
    case unsigned
    case bytes(Int)
    case text
    case array
    case map
    case boolean
  }

  /// Lengths the registry fixes for identifier and digest fields.
  private enum Size {
    static let operationIdentifier = 16
    static let digest = 32
  }

  private static let operationIdentifier = Shape.bytes(Size.operationIdentifier)
  private static let requestHash = Shape.bytes(Size.digest)
  private static let challenge = Shape.bytes(Size.digest)

  internal static let closeReasons: Set<String> = [
    "user_disconnect", "policy", "credential_rejected", "protocol_violation",
    "pairing_revoked", "card_unavailable", "shutdown",
  ]

  internal static let operationStatuses: Set<String> = [
    "completed", "denied", "cancelled", "rejected", "credential_rejected", "ambiguous",
  ]

  internal static let protocolErrors: Set<String> = ["busy", "unknown_operation"]

  internal let name: String
  internal let shape: Shape
  internal let isOptional: Bool

  internal init(_ name: String, _ shape: Shape) {
    self.init(name, shape, optional: false)
  }

  internal init(_ name: String, _ shape: Shape, optional: Bool) {
    self.name = name
    self.shape = shape
    self.isOptional = optional
  }

  /// The registered body schema for each message type.
  internal static func body(for messageType: MessageType) -> [Self] {
    let pairing = pairingBody(for: messageType)
    return pairing.isEmpty ? operationBody(for: messageType) : pairing
  }

  /// Schemas for the pairing, session and liveness messages.
  private static func pairingBody(for messageType: MessageType) -> [Self] {
    switch messageType {
    case .pairingHello:
      [
        Self("parameters", .map), Self("display_name", .text), Self("platform", .text),
        Self("requested_profiles", .array, optional: true),
      ]

    case .pairingConfirm:
      [Self("granted_profiles", .array)]

    case .pairingAbort:
      [Self("reason", .text)]

    case .sessionReady:
      [Self("parameters", .map), Self("nonce", challenge)]

    case .sessionClose:
      [Self("reason", .text), Self("last_received_sequence", .unsigned)]

    case .livenessPing, .livenessPong:
      // The reported position is informational: the cipher state below
      // already refuses anything out of order, so a peer that leaves it out
      // has told this side nothing it did not know. Requiring it made a
      // heartbeat able to end a pairing.
      [
        Self("challenge", challenge),
        Self("last_received_sequence", .unsigned, optional: true),
      ]

    default:
      []
    }
  }

  /// Schemas for the operation messages and the protocol error.
  private static func operationBody(for messageType: MessageType) -> [Self] {
    switch messageType {
    case .operationRequest:
      [
        Self("operation_id", operationIdentifier), Self("profile", .text), Self("action", .text),
        Self("request_hash", requestHash), Self("expires_after_ms", .unsigned),
        Self("context", .map), Self("payload", .map),
      ]

    case .operationPrepared, .operationCommit, .operationResultAck:
      [Self("operation_id", operationIdentifier), Self("request_hash", requestHash)]

    case .operationProgress:
      [
        Self("operation_id", operationIdentifier), Self("request_hash", requestHash),
        Self("event", .text),
      ]

    case .operationCancel:
      [
        Self("operation_id", operationIdentifier), Self("request_hash", requestHash),
        Self("reason", .text, optional: true),
      ]

    case .operationResult:
      [
        Self("operation_id", operationIdentifier), Self("request_hash", requestHash),
        Self("status", .text), Self("error", .text, optional: true), Self("body", .map),
      ]

    case .operationStatusRequest:
      [Self("operation_id", operationIdentifier)]

    case .operationStatus:
      [
        Self("operation_id", operationIdentifier), Self("known", .boolean),
        Self("state", .text, optional: true),
        Self("request_hash", requestHash, optional: true),
      ]

    default:
      [Self("error", .text), Self("operation_id", operationIdentifier, optional: true)]
    }
  }

  internal func accepts(_ value: WireValue) -> Bool {
    switch (shape, value) {
    case (.unsigned, .unsigned), (.text, .text), (.array, .array), (.map, .map),
      (.boolean, .boolean):
      true

    case (.bytes(let length), .bytes(let data)):
      data.count == length

    default:
      false
    }
  }
}
