// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension ProxyOperationEngine {
  private static func closesSession(_ error: ResultError) -> Bool {
    switch error {
    case .retryPolicyRefused, .credentialRejected, .cardCompletionAmbiguous:
      true

    case .userDenied, .requestExpired, .cancelled, .requestInvalidOrUnsupported,
      .cardRemovedBeforeTransmit:
      false
    }
  }

  private static func stale(_ operationIdentifier: Data) -> ProxyDispatch {
    .ignoredStale(
      operationIdentifier: operationIdentifier,
      response: .error(.unknownOperation(operationIdentifier: operationIdentifier)))
  }

  /// Classifies one authenticated peer message.
  internal mutating func receive(
    _ message: TypedMessage,
    store: inout some JournalStore,
    nowMilliseconds: UInt64,
    maximumLifetimeMilliseconds: UInt64
  ) throws -> ProxyDispatch {
    switch message {
    case .operationRequest(let request):
      return try receiveRequest(request)

    case .operationCommit(let reference):
      return try receiveCommit(
        reference, store: &store, nowMilliseconds: nowMilliseconds,
        maximumLifetimeMilliseconds: maximumLifetimeMilliseconds)

    case .operationCancel(let cancellation):
      return try receiveCancel(cancellation, store: &store)

    case .operationResultAck(let reference):
      return try receiveAcknowledgement(reference, store: &store)

    case .operationStatusRequest(let operationIdentifier):
      return .send(.operationStatus(statusReport(for: operationIdentifier)))

    case .error, .other:
      return .notOperation(message)

    case .operationPrepared, .operationResult, .operationStatus, .operationProgress:
      return try refuseRequesterOnlyMessage(message)
    }
  }

  /// Records that the profile's bounded reads finished.
  internal mutating func prerequisitesComplete(operationIdentifier: Data) throws {
    try withOperation(operationIdentifier) { operation in
      do {
        try operation.prerequisitesComplete()
      } catch let error as AuthorizationError {
        throw engineLocalError(error)
      }
    }
  }

  /// Applies the holder's approval of this exact request.
  internal mutating func approve(
    operationIdentifier: Data,
    approval: UserApproval,
    nowMilliseconds: UInt64,
    maximumLifetimeMilliseconds: UInt64
  ) throws -> ProxyDispatch {
    try withOperation(operationIdentifier) { operation in
      let outcome: ApprovalOutcome
      do {
        outcome = try operation.approve(
          approval, nowMilliseconds: nowMilliseconds,
          maximumLifetimeMilliseconds: maximumLifetimeMilliseconds)
      } catch let error as AuthorizationError {
        throw engineLocalError(error)
      }
      switch outcome {
      case .prepared(let reference):
        return .send(.operationPrepared(reference))

      case .executeSafeRead(let read):
        return .executeSafeRead(operationIdentifier: operationIdentifier, read: read)
      }
    }
  }

  /// Retains a completed result before it may be released.
  internal mutating func finishCompleted(
    operationIdentifier: Data, result: OperationResultMessage, store: inout some JournalStore
  ) throws -> ProxyDispatch {
    try withOperation(operationIdentifier) { operation in
      do {
        try operation.finishCompleted(to: &store, result: result)
      } catch let error as AuthorizationError {
        throw engineLocalError(error)
      }
      return .send(.operationResult(result))
    }
  }

  /// Records a stable failure and releases it.
  ///
  /// Three failures also close the session: a refused retry, a rejected
  /// credential, and an ambiguous card completion. Each means the endpoint can
  /// no longer make safe progress on this session.
  internal mutating func finishFailure(
    operationIdentifier: Data, error failure: ResultError, store: inout some JournalStore
  ) throws -> ProxyDispatch {
    try withOperation(operationIdentifier) { operation in
      let result = OperationResultMessage.failure(
        reference: operation.reference, error: failure)
      do {
        try operation.finishFailure(to: &store, result: result)
      } catch let error as AuthorizationError {
        throw engineLocalError(error)
      }
      return .sendFailure(
        message: .operationResult(result), closeSession: Self.closesSession(failure))
    }
  }

  /// Create an authenticated advisory progress message for an active operation.
  internal func reportProgress(
    operationIdentifier: Data, event: ProgressEvent
  ) throws -> TypedMessage {
    guard
      let operation = operations.first(where: { candidate in
        candidate.reference.operationIdentifier == operationIdentifier
      })
    else {
      throw EngineError.unknownLocalOperation
    }
    guard !operation.operationState.isTerminal, event != .unknown else {
      throw EngineError.invalidLocalTransition
    }
    return .operationProgress(
      OperationProgressMessage(reference: operation.reference, event: event))
  }

  /// Classifies every live operation when the session closes.
  ///
  /// Best effort per operation: one record's failed terminal write must
  /// not leave the rest unclassified, and a record that could not be
  /// written stays at its last persisted state, which recovery resolves
  /// the next time this pairing begins operations.
  internal mutating func sessionClosed(
    store: inout some JournalStore
  ) -> [ProxySessionCloseAction] {
    var actions: [ProxySessionCloseAction] = []
    for index in operations.indices {
      let operationIdentifier = operations[index].reference.operationIdentifier
      switch operations[index].stage {
      case .requested, .awaitingConsent, .prepared, .executingSafeRead, .committed:
        guard
          (try? operations[index].receiveCancel(
            to: &store, cancellation: operations[index].reference,
            transmissionProvenNotStarted: true)) != nil
        else { continue }
        actions.append(.cancelled(operationIdentifier: operationIdentifier))

      case .executing:
        actions.append(.continueCardExchange(operationIdentifier: operationIdentifier))

      case .resultPending:
        guard (try? operations[index].deliveryBecameUncertain(to: &store)) != nil else {
          continue
        }
        actions.append(.deliveryUncertain(operationIdentifier: operationIdentifier))

      case .terminal:
        break
      }
    }
    return actions
  }

  private mutating func receiveRequest(_ request: OperationRequest) throws -> ProxyDispatch {
    guard grantedProfiles.contains(request.profile) else {
      throw EngineError.authenticatedProtocolViolation(.profileNotGranted)
    }
    if let index = index(of: request.operationIdentifier) {
      guard operations[index].operationState.isTerminal else {
        throw EngineError.authenticatedProtocolViolation(.activeOperationIdentifierReused)
      }
      return Self.stale(request.operationIdentifier)
    }
    if recovered.contains(where: { candidate in
      candidate.record.operationIdentifier == request.operationIdentifier
    }) {
      return Self.stale(request.operationIdentifier)
    }
    guard !operations.contains(where: { !$0.operationState.isTerminal }) else {
      return .send(.error(.busy))
    }
    let transaction: AuthorizationTransaction
    do {
      transaction = try AuthorizationTransaction(request: request)
    } catch {
      throw EngineError.authenticatedProtocolViolation(.invalidOperationRequest)
    }
    operations.append(transaction)
    return .inspectPrerequisites(operationIdentifier: request.operationIdentifier)
  }

  private mutating func receiveCommit(
    _ reference: OperationReference,
    store: inout some JournalStore,
    nowMilliseconds: UInt64,
    maximumLifetimeMilliseconds: UInt64
  ) throws -> ProxyDispatch {
    let operationIdentifier = reference.operationIdentifier
    guard let index = index(of: operationIdentifier),
      !operations[index].operationState.isTerminal
    else { return Self.stale(operationIdentifier) }

    switch operations[index].stage {
    case .committed, .executing, .resultPending:
      guard operations[index].reference == reference else {
        throw EngineError.authenticatedProtocolViolation(.referenceMismatch)
      }
      return .ignoredDuplicateCommit(operationIdentifier: operationIdentifier)

    default:
      break
    }

    do {
      try operations[index].commit(
        to: &store, requesterCommit: reference, nowMilliseconds: nowMilliseconds,
        maximumLifetimeMilliseconds: maximumLifetimeMilliseconds)
    } catch AuthorizationError.expired {
      return try expireCommitted(index: index, store: &store)
    } catch let error as AuthorizationError {
      throw enginePeerError(error)
    }

    // Telling the holder to execute is also entering execution, the way an
    // approved safe read enters it when its dispatch is made. Emitting the
    // dispatch without the transition left the transaction committed, and a
    // committed transaction refuses the answer the card gives back.
    do {
      _ = try operations[index].beginCardCommand(to: &store)
    } catch let error as AuthorizationError {
      throw engineLocalError(error)
    }
    return .beginCardCommand(operationIdentifier: operationIdentifier)
  }

  /// A commit that arrives after its deadline yields a cancelled result rather
  /// than a violation: a late peer is not a hostile one.
  private mutating func expireCommitted(
    index: Int, store: inout some JournalStore
  ) throws -> ProxyDispatch {
    let result = OperationResultMessage.failure(
      reference: operations[index].reference, error: .requestExpired)
    do {
      try operations[index].finishFailure(to: &store, result: result)
    } catch let error as AuthorizationError {
      throw engineLocalError(error)
    }
    return .send(.operationResult(result))
  }

  private mutating func receiveCancel(
    _ cancellation: CancelMessage, store: inout some JournalStore
  ) throws -> ProxyDispatch {
    let operationIdentifier = cancellation.reference.operationIdentifier
    guard let index = index(of: operationIdentifier),
      !operations[index].operationState.isTerminal
    else { return Self.stale(operationIdentifier) }
    let outcome: ProxyCancelOutcome
    do {
      outcome = try operations[index].receiveCancel(
        to: &store, cancellation: cancellation.reference, transmissionProvenNotStarted: true)
    } catch let error as AuthorizationError {
      throw enginePeerError(error)
    }
    return switch outcome {
    case .cancelled:
      .cancelled(operationIdentifier: operationIdentifier)

    case .advisory:
      .advisoryCancellation(operationIdentifier: operationIdentifier)
    }
  }

  private mutating func receiveAcknowledgement(
    _ reference: OperationReference, store: inout some JournalStore
  ) throws -> ProxyDispatch {
    let operationIdentifier = reference.operationIdentifier
    guard let index = index(of: operationIdentifier),
      !operations[index].operationState.isTerminal
    else { return Self.stale(operationIdentifier) }
    do {
      try operations[index].acknowledgeResult(to: &store, acknowledgement: reference)
    } catch let error as AuthorizationError {
      throw enginePeerError(error)
    }
    return .resultAcknowledged(operationIdentifier: operationIdentifier)
  }

  /// A requester-only message is a violation only when it names a live
  /// operation; otherwise it is a stale race or no operation message at all.
  private func refuseRequesterOnlyMessage(_ message: TypedMessage) throws -> ProxyDispatch {
    guard let operationIdentifier = message.referencedOperationIdentifier else {
      return .notOperation(message)
    }
    guard let index = index(of: operationIdentifier),
      !operations[index].operationState.isTerminal
    else { return Self.stale(operationIdentifier) }
    throw EngineError.authenticatedProtocolViolation(.illegalMessageForActiveOperation)
  }

  private func statusReport(for operationIdentifier: Data) -> StatusReport {
    if let index = index(of: operationIdentifier) {
      return StatusReport(
        operationIdentifier: operationIdentifier,
        known: true,
        state: operations[index].operationState,
        requestHash: operations[index].reference.requestHash)
    }
    if let entry = recovered.first(where: { candidate in
      candidate.record.operationIdentifier == operationIdentifier
    }) {
      return StatusReport(
        operationIdentifier: operationIdentifier,
        known: true,
        state: entry.record.state,
        requestHash: entry.record.requestHash)
    }
    return StatusReport(operationIdentifier: operationIdentifier, known: false)
  }

  private mutating func withOperation<Answer>(
    _ operationIdentifier: Data, _ body: (inout AuthorizationTransaction) throws -> Answer
  ) throws -> Answer {
    guard let index = index(of: operationIdentifier) else {
      throw EngineError.unknownLocalOperation
    }
    return try body(&operations[index])
  }

  private func index(of operationIdentifier: Data) -> Int? {
    operations.firstIndex { $0.reference.operationIdentifier == operationIdentifier }
  }
}
