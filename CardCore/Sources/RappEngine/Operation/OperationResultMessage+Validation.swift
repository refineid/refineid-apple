// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension OperationResultMessage {
  /// A completed result carrying its answer.
  internal static func completed(
    operationIdentifier: RappOperationIdentifier, result: CardOperationResult
  ) -> OperationResultMessage {
    OperationResultMessage(
      operationIdentifier: operationIdentifier, status: .completed,
      response: ResultResponse(result))
  }

  /// A result that did not complete, whose status and error the failure
  /// fixes.
  internal static func failure(
    operationIdentifier: RappOperationIdentifier, failure: ProxyFailure
  ) -> OperationResultMessage {
    rejection(
      operationIdentifier: operationIdentifier, status: failure.status, error: failure.error)
  }

  /// A result that did not complete, naming its status and error.
  internal static func rejection(
    operationIdentifier: RappOperationIdentifier, status: ResultStatus, error: ResultError
  ) -> OperationResultMessage {
    OperationResultMessage(operationIdentifier: operationIdentifier, status: status, error: error)
  }

  /// Checks that the result names `operationIdentifier`, that its status,
  /// error and response agree, and that a completed response answers
  /// `operation`.
  internal func validate(for operationIdentifier: RappOperationIdentifier, operation: CardOperation)
    throws
  {
    guard self.operationIdentifier == operationIdentifier else {
      throw CardOperationError.operationMismatch
    }
    guard isConsistent else { throw CardOperationError.invalidField(field: "result") }
    if response != nil {
      _ = try typedResult(for: operation)
    }
  }

  /// The typed answer a completed response carries for `operation`.
  internal func typedResult(for operation: CardOperation) throws -> CardOperationResult {
    guard let response else { throw CardOperationError.invalidField(field: "response") }
    let result = try response.typed(for: operation)
    guard result.answers(operation) else { throw CardOperationError.profileActionMismatch }
    return result
  }
}
