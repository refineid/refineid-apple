// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The requester's operations on one session: one live at a time, every
/// identifier used once.
///
/// Nothing outlives the session; a requester that did not receive a result
/// starts a new operation (RAPP v26.10.29 §8.1 item 3).
internal struct RequesterOperationEngine {
  private var live: OperationRequest?

  private var used: Set<RappOperationIdentifier> = []

  internal init() {
    self.live = nil
  }

  /// Starts an operation; the returned message is its `operation.request`.
  internal mutating func begin(_ request: OperationRequest) throws -> TypedMessage {
    guard live == nil else { throw EngineError.liveOperation }
    guard !used.contains(request.operationIdentifier) else {
      throw EngineError.duplicateLocalOperationIdentifier
    }
    do {
      try request.validate()
    } catch {
      throw EngineError.invalidLocalValue
    }
    used.insert(request.operationIdentifier)
    live = request
    return .operationRequest(request)
  }

  /// Classifies one authenticated inbound message.
  ///
  /// - Throws: ``EngineError/authenticatedProtocolViolation(_:)`` when the
  ///   custodian sends a message only a requester sends, or a result that
  ///   does not answer the live request; the session closes.
  internal mutating func receive(_ message: TypedMessage) throws -> RequesterDispatch {
    switch message {
    case .cardStatus(let status):
      return .cardStatus(status)

    case .error(let error):
      return receiveError(error)

    case .operationProgress(let progress):
      guard live?.operationIdentifier == progress.operationIdentifier else {
        return .ignored(operationIdentifier: progress.operationIdentifier)
      }
      return .progress(operationIdentifier: progress.operationIdentifier, event: progress.event)

    case .operationResult(let result):
      return try receiveResult(result)

    case .operationRequest, .operationRequestRefused:
      throw EngineError.authenticatedProtocolViolation(.requesterOnlyMessage)

    case .other:
      return .notOperation(message)
    }
  }

  /// The session closed: the live operation, if any, is lost with it.
  internal mutating func sessionClosed() -> RappOperationIdentifier? {
    used = []
    defer { live = nil }
    return live?.operationIdentifier
  }

  private mutating func receiveResult(_ result: OperationResultMessage) throws
    -> RequesterDispatch
  {
    let operationIdentifier = result.operationIdentifier
    guard let request = live, request.operationIdentifier == operationIdentifier else {
      return .ignored(operationIdentifier: operationIdentifier)
    }
    live = nil
    do {
      try result.validate(for: operationIdentifier, operation: request.operation)
    } catch {
      throw EngineError.authenticatedProtocolViolation(.invalidResult)
    }
    if result.status == .completed {
      do {
        return .completed(
          operationIdentifier: operationIdentifier,
          result: try result.typedResult(for: request.operation))
      } catch {
        throw EngineError.authenticatedProtocolViolation(.invalidResult)
      }
    }
    guard let error = result.error else {
      throw EngineError.authenticatedProtocolViolation(.invalidResult)
    }
    return .ended(operationIdentifier: operationIdentifier, status: result.status, error: error)
  }

  private mutating func receiveError(_ error: ProtocolErrorMessage) -> RequesterDispatch {
    guard let operationIdentifier = error.operationIdentifier else {
      return .peerError(error.error)
    }
    guard live?.operationIdentifier == operationIdentifier else {
      return .ignored(operationIdentifier: operationIdentifier)
    }
    live = nil
    return .refused(operationIdentifier: operationIdentifier, error: error.error)
  }
}
