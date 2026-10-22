// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One `operation.progress` (RAPP v26.10.22 §7.1).
internal struct OperationProgressMessage: Equatable {
  internal let operationIdentifier: RappOperationIdentifier
  internal let event: ProgressEvent

  internal var wireBody: [String: WireValue] {
    ["operation_id": .bytes(operationIdentifier.bytes), "event": .text(event.rawValue)]
  }

  internal static func from(wireBody: [String: WireValue]) throws -> Self {
    var body = wireBody
    let decodedOperationIdentifier = try takeOperationIdentifier(&body, "operation_id")
    guard let decodedEvent = ProgressEvent(rawValue: try takeOperationText(&body, "event")) else {
      throw CardOperationError.invalidField(field: "event")
    }
    guard body.isEmpty else { throw CardOperationError.unexpectedField }
    return Self(operationIdentifier: decodedOperationIdentifier, event: decodedEvent)
  }
}
