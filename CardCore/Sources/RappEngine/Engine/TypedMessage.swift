// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One typed message on an authenticated session.
///
/// The engines dispatch on this rather than on raw envelopes, so the wire
/// layer stays the only place that parses bytes.
internal enum TypedMessage: Equatable {
  case error(ProtocolErrorMessage)
  case operationCancel(CancelMessage)
  case operationCommit(OperationReference)
  case operationPrepared(OperationReference)
  case operationProgress(OperationProgressMessage)
  case operationRequest(OperationRequest)
  case operationResult(OperationResultMessage)
  case operationResultAck(OperationReference)
  case operationStatus(StatusReport)
  case operationStatusRequest(operationIdentifier: Data)
  /// A message outside the operation protocol, such as liveness.
  case other(MessageType)

  /// The operation an operation message refers to, if it refers to one.
  ///
  /// A message with no reference belongs to no operation instance, so it can
  /// never be a stale-reference race.
  internal var referencedOperationIdentifier: Data? {
    switch self {
    case .operationRequest(let request):
      request.operationIdentifier

    case .operationPrepared(let reference),
      .operationCommit(let reference),
      .operationResultAck(let reference):
      reference.operationIdentifier

    case .operationProgress(let progress):
      progress.reference.operationIdentifier

    case .operationCancel(let cancellation):
      cancellation.reference.operationIdentifier

    case .operationResult(let result):
      result.operationIdentifier

    case .operationStatusRequest(let operationIdentifier):
      operationIdentifier

    case .operationStatus(let report):
      report.operationIdentifier

    case .error, .other:
      nil
    }
  }
}
