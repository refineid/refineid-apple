// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

extension RappNoiseAndEnvelopeCorpusSupport {
  // MARK: Functions

  /// The first rule of RAPP v26.10.22 §7.1 and §7.2 a decoded `liveness.ping`
  /// envelope breaks, named as the engine names it; nil when it keeps them all.
  internal static func validateEnvelope(_ value: CBORValue) -> String? {
    guard case .map(let envelope) = value else { return "WrongType { field: \"envelope\" }" }
    if let failure = validateEnvelopeVersion(envelope) {
      return failure
    }
    if let failure = validateEnvelopeIdentity(envelope) {
      return failure
    }
    guard case .map(let body)? = envelope["body"] else {
      return "WrongType { field: \"body\" }"
    }
    return validateEnvelopeBody(body)
  }

  private static func validateEnvelopeVersion(_ envelope: [String: CBORValue]) -> String? {
    let allowed: Set<String> = ["version", "session_id", "sequence", "type", "body"]
    guard Set(envelope.keys).isSubset(of: allowed) else { return "UnknownField" }

    guard let version = envelope["version"] else { return "MissingField { field: \"version\" }" }
    guard case .array(let parts) = version else { return "WrongType { field: \"version\" }" }
    guard
      parts == [
        .unsigned(wire.major),
        .unsigned(wire.minor),
        .unsigned(wire.patch),
      ]
    else {
      return "UnsupportedVersion"
    }
    return nil
  }

  private static func validateEnvelopeIdentity(_ envelope: [String: CBORValue]) -> String? {
    guard case .bytes(let sessionID)? = envelope["session_id"] else {
      return "WrongType { field: \"session_id\" }"
    }
    guard sessionID.count == Constants.sessionIDLength else {
      return "WrongLength { field: \"session_id\", expected: 16, got: \(sessionID.count) }"
    }
    guard case .unsigned? = envelope["sequence"] else { return "WrongType { field: \"sequence\" }" }
    guard case .text(let type)? = envelope["type"] else { return "WrongType { field: \"type\" }" }
    guard messageTypes.contains(type) else { return "UnknownMessageType" }
    return nil
  }

  private static func validateEnvelopeBody(_ body: [String: CBORValue]) -> String? {
    guard
      Set(body.keys) == ["challenge"],
      case .bytes(let challenge)? = body["challenge"],
      challenge.count == Constants.challengeLength
    else { return "WrongType { field: \"body\" }" }
    return nil
  }
}
