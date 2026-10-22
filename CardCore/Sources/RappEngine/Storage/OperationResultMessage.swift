// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One `operation.result` (RAPP v26.10.22 §7.1).
///
/// The response stays the map the wire carries: only the requester, which
/// knows the operation it asked for, reads it as a typed answer.
internal struct OperationResultMessage: Equatable {
  internal var operationIdentifier: RappOperationIdentifier
  internal var status: ResultStatus
  internal var error: ResultError?
  internal var response: ResultResponse?

  /// The body fields this result puts on the wire.
  internal var wireBody: [String: WireValue] {
    var body: [String: WireValue] = [
      "operation_id": .bytes(operationIdentifier.bytes),
      "status": .text(status.rawValue),
    ]
    if let response {
      body["response"] = .map(response.fields)
    }
    if let error {
      body["error"] = .text(error.rawValue)
    }
    return body
  }

  /// Whether the status, error, and response agree: a completed result
  /// carries a response and no error; every other status carries an error
  /// the registry pairs with it, and no response (§8.2 item 5, §10.3).
  internal var isConsistent: Bool {
    switch (status, error, response) {
    case (.completed, .none, .some):
      true

    case (_, .some(let error), .none):
      status != .completed && error.permits(status)

    default:
      false
    }
  }

  /// A received `operation.result` body.
  internal static func from(wireBody: [String: WireValue]) throws -> Self {
    var map = wireBody
    let decodedOperationIdentifier = try takeOperationIdentifier(&map, "operation_id")
    guard let decodedStatus = ResultStatus(rawValue: try takeOperationText(&map, "status")) else {
      throw CardOperationError.invalidField(field: "status")
    }
    var message = Self(operationIdentifier: decodedOperationIdentifier, status: decodedStatus)
    if map["error"] != nil {
      guard let decodedError = ResultError(rawValue: try takeOperationText(&map, "error")) else {
        throw CardOperationError.invalidField(field: "error")
      }
      message.error = decodedError
    }
    if map["response"] != nil {
      message.response = ResultResponse(fields: try takeOperationMap(&map, "response"))
    }
    guard map.isEmpty else { throw CardOperationError.unexpectedField }
    guard message.isConsistent else { throw CardOperationError.invalidField(field: "result") }
    return message
  }
}
