// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension OperationResultMessage {
  /// A completed result carrying its answer.
  internal static func completed(
    reference: OperationReference, result: CardOperationResult
  ) -> OperationResultMessage {
    OperationResultMessage(
      operationIdentifier: reference.operationIdentifier,
      requestHash: reference.requestHash,
      status: .completed,
      response: ResultResponse(fields: wireResponse(result)))
  }

  /// A non-successful result whose status and error the failure fixes.
  internal static func failure(
    reference: OperationReference, failure: ProxyFailure
  ) -> OperationResultMessage {
    OperationResultMessage(
      operationIdentifier: reference.operationIdentifier,
      requestHash: reference.requestHash,
      status: failure.status,
      error: failure.error)
  }

  /// The result a retired operation answers with (section 8.2.5).
  ///
  /// The preserved disposition is honoured: a retired failure is never
  /// reported as completed, and no pruned response travels.
  internal static func retired(
    reference: OperationReference, disposition: ResultStatus, preservedError: ResultError?
  ) -> OperationResultMessage {
    OperationResultMessage(
      operationIdentifier: reference.operationIdentifier,
      requestHash: reference.requestHash,
      status: disposition,
      error: disposition == .completed
        ? .operationAlreadyRetired : (preservedError ?? .operationFailed),
      retired: true)
  }

  /// Checks the hash binding, the status and error pairing, and that a
  /// completed response answers the operation it claims to answer.
  internal func validate(
    for reference: OperationReference, operation: CardOperation
  ) throws {
    guard operationIdentifier == reference.operationIdentifier,
      requestHash == reference.requestHash
    else { throw CardOperationError.requestHashMismatch }
    guard isConsistent else { throw CardOperationError.invalidField(field: "result") }
    if status == .completed, response != nil {
      _ = try typedResult(for: operation)
    }
  }

  /// The typed answer a completed response carries for `operation`.
  internal func typedResult(for operation: CardOperation) throws -> CardOperationResult {
    guard let response else { throw CardOperationError.invalidField(field: "response") }
    do {
      let result = try cardResult(fromResponse: response.fields, for: operation)
      guard result.answers(operation) else { throw CardOperationError.profileActionMismatch }
      return result
    } catch let error as CardOperationError {
      throw error
    } catch {
      throw CardOperationError.invalidField(field: "response")
    }
  }
}
