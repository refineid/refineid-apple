// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The identifier and hash echo carried by results, acknowledgements,
/// progress, and status messages.
internal struct OperationReference: Equatable {
  internal let operationIdentifier: Data

  internal let requestHash: Data

  internal var wireBody: [String: WireValue] {
    ["operation_id": .bytes(operationIdentifier), "request_hash": .bytes(requestHash)]
  }

  internal init(operationIdentifier: Data, requestHash: Data) {
    self.operationIdentifier = operationIdentifier
    self.requestHash = requestHash
  }

  internal init(of request: OperationRequest) throws {
    self.operationIdentifier = request.operationIdentifier
    self.requestHash = try request.requestHash()
  }

  internal static func from(wireBody: [String: WireValue]) throws -> Self {
    var body = wireBody
    let decodedOperationIdentifier = try takeOperationBytes(&body, "operation_id")
    let decodedRequestHash = try takeOperationBytes(&body, "request_hash")
    guard body.isEmpty else { throw CardOperationError.unexpectedField }
    guard decodedOperationIdentifier.count == OperationSize.operationIdentifier,
      decodedRequestHash.count == OperationSize.requestHash
    else { throw CardOperationError.invalidIdentifier }
    return Self(
      operationIdentifier: decodedOperationIdentifier, requestHash: decodedRequestHash
    )
  }
}
