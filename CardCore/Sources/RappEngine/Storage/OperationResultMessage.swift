// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One `operation.result` (RAPP v26.10.1 §7.1), as carried on the wire and
/// retained until the requester acknowledges it.
///
/// The response stays the map the wire carries: only the requester, which
/// knows the operation it asked for, reads it as a typed answer.
internal struct OperationResultMessage: Equatable {
  internal var operationIdentifier: Data
  internal var requestHash: Data
  internal var status: ResultStatus
  internal var error: ResultError?
  internal var response: ResultResponse?
  internal var remainingRetries: UInt8?
  internal var retired = false

  /// The body fields this result puts on the wire.
  internal var wireBody: [String: WireValue] {
    var body: [String: WireValue] = [
      "operation_id": .bytes(operationIdentifier),
      "request_hash": .bytes(requestHash),
      "status": .text(status.rawValue),
    ]
    if let response {
      body["response"] = .map(response.fields)
    }
    if let error {
      body["error"] = .text(error.rawValue)
    }
    if let remainingRetries {
      body["remaining_retries"] = .unsigned(UInt64(remainingRetries))
    }
    if retired {
      body["retired"] = .boolean(true)
    }
    return body
  }

  /// Whether the status, error, and response agree.
  ///
  /// A live completed result carries a response and no error; a retired one
  /// carries `operation_already_retired` and no response; every other status
  /// carries an error its registry pairs with that status. An ambiguous
  /// result may also carry a batch's partial progress (RAPP v26.10.1 §9.3).
  internal var isConsistent: Bool {
    switch (status, error, response) {
    case (.completed, .none, .some):
      return !retired

    case (.completed, .some(let error), .none):
      return retired && error == .operationAlreadyRetired

    case (.ambiguous, .some(let error), .some):
      return !retired && error.permits(status)

    case (_, .some(let error), .none):
      return status != .completed && error.permits(status)

    default:
      return false
    }
  }

  internal static func decode(_ bytes: Data) throws -> Self {
    var map = try decodedMap(bytes)
    let decodedOperationIdentifier = try takeBytes(&map, "operation_id")
    let decodedRequestHash = try takeBytes(&map, "request_hash")
    guard decodedOperationIdentifier.count == JournalSize.operationIdentifier,
      decodedRequestHash.count == JournalSize.requestHash
    else { throw PairRecordError.invalidInput }
    guard let decodedStatus = ResultStatus(rawValue: try takeText(&map, "status")) else {
      throw PairRecordError.invalidInput
    }
    var message = Self(
      operationIdentifier: decodedOperationIdentifier,
      requestHash: decodedRequestHash,
      status: decodedStatus)
    try message.takeOptionalFields(from: &map)
    guard map.isEmpty, message.isConsistent else { throw PairRecordError.invalidInput }
    return message
  }

  /// Reads the fields a result may omit, refusing any of the wrong type.
  private mutating func takeOptionalFields(from map: inout [String: WireValue]) throws {
    if map["error"] != nil {
      error = ResultError(wireName: try takeText(&map, "error"))
    }
    switch map.removeValue(forKey: "response") {
    case .none:
      break

    case .some(.map(let fields)):
      response = ResultResponse(fields: fields)

    case .some:
      throw PairRecordError.invalidInput
    }
    if map["remaining_retries"] != nil {
      guard let count = UInt8(exactly: try takeUnsigned(&map, "remaining_retries")) else {
        throw PairRecordError.invalidInput
      }
      remainingRetries = count
    }
    retired = try takeBoolean(&map, "retired", absent: false)
  }

  internal func encoded() throws -> Data {
    do {
      return try WireValue.map(wireBody).encoded()
    } catch {
      throw PairRecordError.invalidInput
    }
  }
}
