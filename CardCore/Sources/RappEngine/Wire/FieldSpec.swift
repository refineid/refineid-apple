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
    static let pairIdentifier = 16
    static let digest = 32
  }

  private static let operationIdentifier = Shape.bytes(Size.operationIdentifier)
  private static let pairIdentifier = Shape.bytes(Size.pairIdentifier)
  private static let fingerprint = Shape.bytes(Size.digest)
  private static let challenge = Shape.bytes(Size.digest)

  /// `close-reason-val` (RAPP v26.10.22 §7.1).
  internal static let closeReasons: Set<String> = [
    "normal", "complete", "user_disconnect", "policy", "protocol_violation", "pairing_revoked",
    "shutdown", "card_unavailable", "service_withdrawn",
  ]

  /// `operation-status-val` (RAPP v26.10.22 §7.1).
  internal static let operationStatuses: Set<String> = ["completed", "rejected", "cancelled"]

  /// Bounds on the error body's text fields (RAPP v26.10.22 §10.3).
  internal static let errorNameLengths = 1...64
  internal static let errorMessageLengths = 1...512

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

    case .pairingStored:
      [Self("pair_id", pairIdentifier)]

    case .cardStatus:
      [Self("card_present", .boolean), Self("certificate_fingerprint", fingerprint)]

    case .sessionReady:
      [Self("parameters", .map), Self("nonce", challenge)]

    case .sessionClose:
      [Self("reason", .text)]

    case .livenessPing, .livenessPong:
      [Self("challenge", challenge)]

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
        Self("context", .map), Self("payload", .map),
        Self("expires_after_ms", .unsigned, optional: true),
      ]

    case .operationProgress:
      [Self("operation_id", operationIdentifier), Self("event", .text)]

    case .operationResult:
      [
        Self("operation_id", operationIdentifier), Self("status", .text),
        Self("response", .map, optional: true), Self("error", .text, optional: true),
      ]

    default:
      [
        Self("error_name", .text), Self("message", .text),
        Self("operation_id", operationIdentifier, optional: true),
      ]
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
