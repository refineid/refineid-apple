// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension ProxyOperationEngine {
  /// The `card.status` message the custodian sends after `session.ready`
  /// and on every change (RAPP v26.10.22 §8.4).
  internal static func reportCardStatus(_ status: RappCardStatus) -> TypedMessage {
    .cardStatus(status)
  }

  /// Classifies one authenticated peer message.
  ///
  /// - Throws: ``EngineError/authenticatedProtocolViolation(_:)`` when the
  ///   requester sends a message only a custodian sends; the session closes.
  internal mutating func receive(_ message: TypedMessage) throws -> ProxyDispatch {
    switch message {
    case .operationRequest(let request):
      return receiveRequest(request)

    case .operationRequestRefused(let refusal):
      if let answer = admissionRefusal(refusal.operationIdentifier) { return answer }
      return .send(
        .operationResult(
          .rejection(
            operationIdentifier: refusal.operationIdentifier, status: .rejected,
            error: refusal.error)))

    case .operationResult, .operationProgress, .cardStatus:
      throw EngineError.authenticatedProtocolViolation(.custodianOnlyMessage)

    case .error, .other:
      return .notOperation(message)
    }
  }

  /// The operation has the card and its prerequisite reads are done.
  ///
  /// An action that needs a PIN waits for it; a read asks the holder nothing
  /// and runs (§8.2 items 3 and 6). An operation whose deadline has passed is
  /// cancelled instead (§8.1 item 2).
  internal mutating func prerequisitesComplete(
    operationIdentifier: RappOperationIdentifier,
    nowMilliseconds: UInt64,
    maximumLifetimeMilliseconds: UInt64
  ) throws -> ProxyDispatch {
    guard var operation = live, operation.operationIdentifier == operationIdentifier else {
      throw EngineError.unknownLocalOperation
    }
    if operation.stage == .requested,
      operation.isExpired(
        nowMilliseconds: nowMilliseconds,
        maximumLifetimeMilliseconds: maximumLifetimeMilliseconds)
    {
      return try finishFailure(operationIdentifier: operationIdentifier, failure: .requestExpired)
    }
    let outcome: PrerequisitesOutcome
    do {
      outcome = try operation.prerequisitesComplete()
    } catch {
      throw EngineError.invalidLocalTransition
    }
    live = operation
    switch outcome {
    case .awaitConsent:
      return .awaitConsent(operationIdentifier: operationIdentifier)

    case .executeSafeRead(let read):
      return .executeSafeRead(operationIdentifier: operationIdentifier, read: read)
    }
  }

  /// Applies the holder's approval.
  ///
  /// An approval after the request's deadline cancels the operation instead and
  /// no card command exists (§8.1 item 2).
  internal mutating func approve(
    operationIdentifier: RappOperationIdentifier,
    approval: UserApproval,
    nowMilliseconds: UInt64,
    maximumLifetimeMilliseconds: UInt64
  ) throws -> ProxyDispatch {
    guard var operation = live, operation.operationIdentifier == operationIdentifier else {
      throw EngineError.unknownLocalOperation
    }
    if operation.stage == .awaitingConsent,
      operation.isExpired(
        nowMilliseconds: nowMilliseconds,
        maximumLifetimeMilliseconds: maximumLifetimeMilliseconds)
    {
      return try finishFailure(operationIdentifier: operationIdentifier, failure: .requestExpired)
    }
    let command: AuthorizedCardCommand
    do {
      command = try operation.approve(
        approval, nowMilliseconds: nowMilliseconds,
        maximumLifetimeMilliseconds: maximumLifetimeMilliseconds
      )
      .execute { $0 }
    } catch {
      throw EngineError.invalidLocalTransition
    }
    live = operation
    return .executeCardCommand(operationIdentifier: operationIdentifier, command: command)
  }

  /// Cancels the live operation when its deadline passed before the card
  /// was commanded, waiting in the queue or for its PIN (§8.1 item 2); `nil`
  /// when nothing is due.
  internal mutating func expireDue(
    nowMilliseconds: UInt64, maximumLifetimeMilliseconds: UInt64
  ) throws -> ProxyDispatch? {
    guard let operation = live,
      operation.stage == .requested || operation.stage == .awaitingConsent,
      operation.isExpired(
        nowMilliseconds: nowMilliseconds,
        maximumLifetimeMilliseconds: maximumLifetimeMilliseconds)
    else { return nil }
    return try finishFailure(
      operationIdentifier: operation.operationIdentifier, failure: .requestExpired)
  }

  /// Ends the operation with its completed result.
  internal mutating func finishCompleted(
    operationIdentifier: RappOperationIdentifier, result: OperationResultMessage
  ) throws -> ProxyDispatch {
    try withLive(operationIdentifier) { try $0.finishCompleted(result) }
    return .send(.operationResult(result))
  }

  /// Ends the operation with a result that did not complete.
  internal mutating func finishFailure(
    operationIdentifier: RappOperationIdentifier, failure: ProxyFailure
  ) throws -> ProxyDispatch {
    let result = OperationResultMessage.failure(
      operationIdentifier: operationIdentifier, failure: failure)
    try withLive(operationIdentifier) { try $0.finishFailure(result) }
    return .send(.operationResult(result))
  }

  /// Records one batch signature as the card makes it.
  internal mutating func recordBatchSignature(
    operationIdentifier: RappOperationIdentifier, signature: Data
  ) throws {
    try withLive(operationIdentifier) { try $0.recordBatchSignature(signature) }
  }

  /// Answers a batch once every document is signed, with exactly those
  /// signatures.
  internal mutating func completeBatch(operationIdentifier: RappOperationIdentifier) throws
    -> ProxyDispatch
  {
    guard let operation = live, operation.operationIdentifier == operationIdentifier else {
      throw EngineError.unknownLocalOperation
    }
    return try finishCompleted(
      operationIdentifier: operationIdentifier,
      result: .completed(
        operationIdentifier: operationIdentifier,
        result: .signatures(operation.batchSignatures)))
  }

  /// A progress message for the live operation.
  internal func reportProgress(
    operationIdentifier: RappOperationIdentifier, event: ProgressEvent
  ) throws -> TypedMessage {
    guard let operation = live, operation.operationIdentifier == operationIdentifier else {
      throw EngineError.unknownLocalOperation
    }
    guard !operation.isTerminal else { throw EngineError.invalidLocalTransition }
    return .operationProgress(
      OperationProgressMessage(operationIdentifier: operationIdentifier, event: event))
  }

  /// The session closed: every operation of it is over (§8.1 item 3).
  ///
  /// A card command in progress runs to the card's answer, which is discarded;
  /// anything else is dropped.
  internal mutating func sessionClosed() -> ProxySessionCloseAction? {
    seen = []
    guard let operation = live else { return nil }
    live = nil
    switch operation.stage {
    case .terminal:
      return nil

    case .executing, .executingSafeRead:
      return .continueCardExchange(operationIdentifier: operation.operationIdentifier)

    case .requested, .awaitingConsent:
      return .dropped(operationIdentifier: operation.operationIdentifier)
    }
  }

  private mutating func receiveRequest(_ request: OperationRequest) -> ProxyDispatch {
    let operationIdentifier = request.operationIdentifier
    if let answer = admissionRefusal(operationIdentifier) { return answer }
    guard grantedProfiles.contains(request.profile) else {
      return .send(
        .operationResult(
          .failure(operationIdentifier: operationIdentifier, failure: .unauthorized)))
    }
    live = AuthorizationTransaction(request: request)
    return .inspectPrerequisites(operationIdentifier: operationIdentifier)
  }

  /// The `error` that refuses a request before admission: an identifier the
  /// session has seen, or a second request while one is live (§8.1 item 1).
  ///
  /// Every identifier counts as seen from here on.
  private mutating func admissionRefusal(_ operationIdentifier: RappOperationIdentifier)
    -> ProxyDispatch?
  {
    guard seen.insert(operationIdentifier).inserted else {
      return .send(.error(.duplicate(operationIdentifier)))
    }
    if let live, !live.isTerminal {
      return .send(.error(.busy(operationIdentifier)))
    }
    return nil
  }

  private mutating func withLive(
    _ operationIdentifier: RappOperationIdentifier,
    _ body: (inout AuthorizationTransaction) throws -> Void
  ) throws {
    guard var operation = live, operation.operationIdentifier == operationIdentifier else {
      throw EngineError.unknownLocalOperation
    }
    do {
      try body(&operation)
    } catch {
      throw EngineError.invalidLocalTransition
    }
    live = operation
  }
}
