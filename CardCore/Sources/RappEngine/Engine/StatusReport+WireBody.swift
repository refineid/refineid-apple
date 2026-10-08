// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension OperationState {
  /// `operation-state-val` (RAPP v26.10.1 §7.1) for this journal state.
  ///
  /// Every stage before a terminal outcome reads as `in_flight`; a completed
  /// result reads as completed whether or not it was acknowledged, and the
  /// report's `retired` flag tells the two apart.
  internal var wireStateName: String {
    switch self {
    case .idle, .requested, .awaitingConsent, .prepared, .committed, .executing:
      "in_flight"

    case .resultPending, .completed, .deliveryUncertain:
      ResultStatus.completed.rawValue

    case .denied, .rejected:
      ResultStatus.rejected.rawValue

    case .cancelled:
      ResultStatus.cancelled.rawValue

    case .credentialRejected:
      ResultStatus.credentialRejected.rawValue

    case .ambiguous:
      ResultStatus.ambiguous.rawValue
    }
  }

  /// The journal state a received `operation-state-val` names.
  internal init?(wireStateName: String) {
    switch wireStateName {
    case "in_flight":
      self = .executing

    case ResultStatus.completed.rawValue:
      self = .completed

    case ResultStatus.rejected.rawValue:
      self = .rejected

    case ResultStatus.cancelled.rawValue:
      self = .cancelled

    case ResultStatus.credentialRejected.rawValue:
      self = .credentialRejected

    case ResultStatus.ambiguous.rawValue:
      self = .ambiguous

    default:
      return nil
    }
  }
}

extension StatusReport {
  /// The exact `operation.status` wire body.
  ///
  /// A known operation always states whether it is retired; an unknown one
  /// omits `state`, `request_hash` and `retired` entirely. This is
  /// deliberately NOT the journal's encoding, which writes absent values as
  /// explicit null to keep its map arity constant.
  internal var wireBody: [String: WireValue] {
    var body: [String: WireValue] = [
      "operation_id": .bytes(operationIdentifier),
      "known": .boolean(known),
    ]
    if let state {
      body["state"] = .text(state.wireStateName)
    }
    if let requestHash {
      body["request_hash"] = .bytes(requestHash)
    }
    if known {
      body["retired"] = .boolean(retired)
    }
    return body
  }

  /// A received `operation.status` body.
  internal static func from(wireBody: [String: WireValue]) throws -> Self {
    var body = wireBody
    let operationIdentifier = try takeBytes(&body, "operation_id")
    let known = try takeBoolean(&body, "known")
    var report = Self(operationIdentifier: operationIdentifier, known: known)
    if case .text(let name)? = body.removeValue(forKey: "state") {
      guard let state = OperationState(wireStateName: name) else {
        throw PairRecordError.invalidInput
      }
      report.state = state
    }
    if case .bytes(let hash)? = body.removeValue(forKey: "request_hash") {
      report.requestHash = hash
    }
    report.retired = try takeBoolean(&body, "retired", absent: false)
    guard body.isEmpty else { throw PairRecordError.invalidInput }
    return report
  }
}
