// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension TypedMessage {
  /// The registered message type, for messages that carry one.
  internal var messageType: MessageType? {
    switch self {
    case .operationRequest:
      .operationRequest

    case .operationPrepared:
      .operationPrepared

    case .operationProgress:
      .operationProgress

    case .operationCommit:
      .operationCommit

    case .operationCancel:
      .operationCancel

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
    }
  }

  /// The exact body this message puts on the wire, as a field map.
  ///
  /// A result carries its own encoder, so it is absent here and reached
  /// through `encodedBody()`. A message outside the operation protocol has no
  /// body here either, because its own layer owns that encoding.
  internal func wireBody() throws -> [String: WireValue]? {
    // swiftlint:disable:previous discouraged_optional_collection
    switch self {
    case .operationRequest(let request):
      try request.wireBody()

    case .operationPrepared(let reference),
      .operationCommit(let reference),
      .operationResultAck(let reference):
      reference.wireBody

    case .operationProgress(let progress):
      progress.wireBody

    case .operationCancel(let cancellation):
      try cancellation.wireBody()

    case .operationStatusRequest(let operationIdentifier):
      ["operation_id": .bytes(operationIdentifier)]

    case .operationStatus(let report):
      report.wireBody

    case .error(let error):
      error.wireBody

    case .operationResult(let result):
      result.wireBody

    case .other:
      nil
    }
  }

  /// The exact body bytes this message puts on the wire.
  internal func encodedBody() throws -> Data? {
    if case .operationResult(let result) = self {
      return try result.encoded()
    }
    guard let body = try wireBody() else { return nil }
    return try WireValue.map(body).encoded()
  }
}
