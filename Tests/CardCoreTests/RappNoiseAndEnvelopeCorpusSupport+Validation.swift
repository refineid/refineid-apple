// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

extension RappNoiseAndEnvelopeCorpusSupport {
  // MARK: Functions

  internal static func validateEnvelope(
    _ value: CBORValue,
    supportedCritical: Set<String>
  ) -> String? {
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
    if let failure = validateEnvelopeBody(body) {
      return failure
    }
    return validateEnvelopeExtras(envelope, supportedCritical: supportedCritical)
  }

  private static func validateEnvelopeExtras(
    _ envelope: [String: CBORValue],
    supportedCritical: Set<String>
  ) -> String? {
    var critical: [String] = []
    if let criticalValue = envelope["critical"] {
      guard case .array(let entries) = criticalValue else {
        return "WrongType { field: \"critical\" }"
      }
      for entry in entries {
        guard case .text(let name) = entry else {
          return "WrongType { field: \"critical\" }"
        }
        critical.append(name)
      }
    }

    var extensions: [String: CBORValue] = [:]
    if let extensionsValue = envelope["extensions"] {
      guard case .map(let entries) = extensionsValue else {
        return "WrongType { field: \"extensions\" }"
      }
      extensions = entries
    }
    guard critical.allSatisfy({ extensions[$0] != nil }) else {
      return "CriticalExtensionMissing"
    }
    guard critical.allSatisfy(supportedCritical.contains) else {
      return "UnsupportedCriticalExtension"
    }
    return nil
  }

  private static func validateEnvelopeVersion(_ envelope: [String: CBORValue]) -> String? {
    let allowed: Set<String> = [
      "version", "session_id", "sequence", "type", "body", "critical", "extensions",
    ]
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
    guard type == "liveness.ping" else { return "UnknownMessageType" }
    return nil
  }

  private static func validateEnvelopeBody(_ body: [String: CBORValue]) -> String? {
    guard
      case .bytes(let challenge)? = body["challenge"],
      challenge.count == Constants.challengeLength,
      case .unsigned? = body["last_received_sequence"]
    else { return "WrongType { field: \"body\" }" }
    return nil
  }
}
