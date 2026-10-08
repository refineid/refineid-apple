// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension TypedMessage {
  /// The registered message type, for messages that carry one.
  internal var messageType: MessageType? {
    switch self {
    case .operationRequest:
      .operationRequest

    case .operationProgress:
      .operationProgress

    case .operationResult:
      .operationResult

    case .operationResultAck:
      .operationResultAck

    case .operationStatusRequest:
      .operationStatusRequest

    case .operationStatus:
      .operationStatus

    case .error:
      .error

    case .other(let type):
      type

    case .operationRequestRefused:
      nil
    }
  }

  /// The exact body this message puts on the wire, as a field map.
  ///
  /// A message outside the operation protocol has no body here, because its
  /// own layer owns that encoding; an inbound refusal has none either.
  internal func wireBody() -> [String: WireValue]? {
    // swiftlint:disable:previous discouraged_optional_collection
    switch self {
    case .operationRequest(let request):
      request.wireBody()

    case .operationResultAck(let reference):
      reference.wireBody

    case .operationProgress(let progress):
      progress.wireBody

    case .operationStatusRequest(let operationIdentifier):
      ["operation_id": .bytes(operationIdentifier)]

    case .operationStatus(let report):
      report.wireBody

    case .error(let error):
      error.wireBody

    case .operationResult(let result):
      result.wireBody

    case .other, .operationRequestRefused:
      nil
    }
  }

  /// The exact body bytes this message puts on the wire.
  internal func encodedBody() throws -> Data? {
    guard let body = wireBody() else { return nil }
    return try WireValue.map(body).encoded()
  }
}
