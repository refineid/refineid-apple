// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One decoded, schema-checked envelope.
internal struct Envelope: Equatable {
  private static let knownFields: Set<String> = [
    "version", "type", "session_id", "sequence", "body",
  ]

  private static var versionValue: WireValue {
    .array([
      .unsigned(RappNoise.wireVersion.major), .unsigned(RappNoise.wireVersion.minor),
      .unsigned(RappNoise.wireVersion.patch),
    ])
  }

  internal let messageType: MessageType
  internal let sessionIdentifier: Data
  internal let sequence: UInt64
  internal let body: [String: WireValue]

  /// Decode and fully validate one envelope plaintext.
  internal static func decode(_ bytes: Data) throws -> Self {
    guard bytes.count <= WireLimits.framePlaintext else {
      throw WireError.oversizedPlaintext(got: bytes.count)
    }
    guard case .map(let fields) = try decodeDeterministicCbor(bytes) else {
      throw WireError.wrongType(field: "envelope")
    }
    guard Set(fields.keys).isSubset(of: knownFields) else { throw WireError.unknownField }

    try requireSupportedVersion(fields)
    let decodedType = try requireMessageType(fields)
    let decodedSession = try requireSessionIdentifier(fields)

    guard case .unsigned(let decodedSequence) = try require(fields, "sequence") else {
      throw WireError.wrongType(field: "sequence")
    }
    guard case .map(let decodedBody) = try require(fields, "body") else {
      throw WireError.wrongType(field: "body")
    }

    do {
      try validate(body: decodedBody, for: decodedType)
    } catch {
      RappRefusalLog.refused(decodedType, because: error)
      throw error
    }

    return Self(
      messageType: decodedType, sessionIdentifier: decodedSession, sequence: decodedSequence,
      body: decodedBody)
  }

  private static func requireSupportedVersion(_ fields: [String: WireValue]) throws {
    guard case .array(let version) = try require(fields, "version") else {
      throw WireError.wrongType(field: "version")
    }
    guard
      version == [
        .unsigned(RappNoise.wireVersion.major), .unsigned(RappNoise.wireVersion.minor),
        .unsigned(RappNoise.wireVersion.patch),
      ]
    else { throw WireError.unsupportedVersion }
  }

  private static func requireMessageType(_ fields: [String: WireValue]) throws -> MessageType {
    guard case .text(let typeName) = try require(fields, "type") else {
      throw WireError.wrongType(field: "type")
    }
    guard let registered = MessageType(rawValue: typeName) else {
      throw WireError.unknownMessageType
    }
    return registered
  }

  private static func requireSessionIdentifier(_ fields: [String: WireValue]) throws -> Data {
    guard case .bytes(let identifier) = try require(fields, "session_id") else {
      throw WireError.wrongType(field: "session_id")
    }
    guard identifier.count == WireLimits.sessionIdentifier else {
      throw WireError.wrongLength(
        field: "session_id", expected: WireLimits.sessionIdentifier, got: identifier.count)
    }
    return identifier
  }

  private static func require(_ fields: [String: WireValue], _ name: String) throws -> WireValue {
    guard let value = fields[name] else { throw WireError.missingField(field: name) }
    return value
  }

  private static func validate(body: [String: WireValue], for messageType: MessageType) throws {
    let specs = FieldSpec.body(for: messageType)
    guard body.keys.allSatisfy({ key in specs.contains { $0.name == key } }) else {
      throw WireError.unknownField
    }
    for spec in specs {
      guard let value = body[spec.name] else {
        if spec.isOptional { continue }
        throw WireError.missingField(field: spec.name)
      }
      guard spec.accepts(value) else { throw WireError.wrongType(field: spec.name) }
    }
    try validateDiscriminants(body: body, for: messageType)
  }

  private static func validateDiscriminants(
    body: [String: WireValue], for messageType: MessageType
  ) throws {
    func discriminant(_ field: String) -> String? {
      if case .text(let value) = body[field] { return value }
      return nil
    }
    switch messageType {
    case .sessionClose:
      guard let reason = discriminant("reason"), FieldSpec.closeReasons.contains(reason) else {
        throw WireError.invalidValue(field: "reason")
      }

    case .operationResult:
      guard let status = discriminant("status"), FieldSpec.operationStatuses.contains(status) else {
        throw WireError.invalidValue(field: "status")
      }

    case .error:
      guard let name = discriminant("error_name"),
        FieldSpec.errorNameLengths.contains(name.utf8.count),
        ResultError(rawValue: name) != nil
      else { throw WireError.invalidValue(field: "error_name") }
      guard let message = discriminant("message"),
        FieldSpec.errorMessageLengths.contains(message.utf8.count)
      else { throw WireError.invalidValue(field: "message") }

    default:
      break
    }
  }

  internal func encoded() throws -> Data {
    let fields: [String: WireValue] = [
      "version": Self.versionValue,
      "type": .text(messageType.rawValue),
      "session_id": .bytes(sessionIdentifier),
      "sequence": .unsigned(sequence),
      "body": .map(body),
    ]
    return try WireValue.map(fields).encoded()
  }
}
