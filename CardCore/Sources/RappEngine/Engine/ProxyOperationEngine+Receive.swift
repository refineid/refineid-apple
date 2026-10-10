// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension ProxyOperationEngine {
  private static func stale(_ operationIdentifier: Data) -> ProxyDispatch {
    .ignoredStale(
      operationIdentifier: operationIdentifier,
      response: .error(.unknownOperation(operationIdentifier: operationIdentifier)))
  }

  /// The result a journaled operation from an earlier session answers with.
  private static func answer(for entry: RecoveredProxyRecord) -> OperationResultMessage {
    let reference = OperationReference(
      operationIdentifier: entry.record.operationIdentifier,
      requestHash: entry.record.requestHash)
    if let retained = entry.retainedResult {
      return retained
    }
    switch entry.record.state {
    case .completed:
      return .retired(reference: reference, disposition: .completed, preservedError: nil)

    case .cancelled, .denied:
      return .failure(reference: reference, failure: .cancelled)

    case .credentialRejected:
      return .failure(reference: reference, failure: .credentialRejected)

    case .ambiguous, .committed, .executing, .resultPending, .deliveryUncertain:
      return .failure(
        reference: reference, failure: .cardCompletionAmbiguous,
        batchSignatures: entry.record.batch?.completedSignatures ?? [])

    case .idle, .requested, .awaitingConsent, .prepared, .rejected:
      return .failure(reference: reference, failure: .retryPolicyRefused)
    }
  }

  /// Classifies one authenticated peer message.
  internal mutating func receive(
    _ message: TypedMessage,
    store: inout some JournalStore,
    nowMilliseconds _: UInt64,
    maximumLifetimeMilliseconds _: UInt64
  ) throws -> ProxyDispatch {
    switch message {
    case .operationRequest(let request):
      return try receiveRequest(request, store: &store)

    case .operationRequestRefused(let refusal):
      return receiveRefusal(refusal)

    case .operationResultAck(let reference):
      return try receiveAcknowledgement(reference, store: &store)

    case .operationStatusRequest(let operationIdentifier):
      return statusAnswer(for: operationIdentifier)

    case .error, .other:
      return .notOperation(message)

    case .operationResult, .operationStatus, .operationProgress:
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
  ///
  /// An approval that arrives after the request's local deadline cancels the
  /// operation instead (section 8.2.1); no card command is ever produced.
  internal mutating func approve(
    operationIdentifier: Data,
    approval: UserApproval,
    store: inout some JournalStore,
    nowMilliseconds: UInt64,
    maximumLifetimeMilliseconds: UInt64
  ) throws -> ProxyDispatch {
    guard let index = index(of: operationIdentifier) else {
      throw EngineError.unknownLocalOperation
    }
    let outcome: ApprovalOutcome
    do {
      outcome = try operations[index].approve(
        approval, to: &store, nowMilliseconds: nowMilliseconds,
        maximumLifetimeMilliseconds: maximumLifetimeMilliseconds)
    } catch AuthorizationError.expired {
      return try finishFailure(
        operationIdentifier: operationIdentifier, failure: .requestExpired, store: &store)
    } catch let error as AuthorizationError {
      throw engineLocalError(error)
    }
    switch outcome {
    case .executeCardCommand:
      return .beginCardCommand(operationIdentifier: operationIdentifier)

    case .executeSafeRead(let read):
      return .executeSafeRead(operationIdentifier: operationIdentifier, read: read)
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
  /// Three failures also close the session: a refused retry, a blocked
  /// credential, and an ambiguous card completion. Each means the endpoint
  /// can no longer make safe progress on this session.
  internal mutating func finishFailure(
    operationIdentifier: Data, failure: ProxyFailure, store: inout some JournalStore
  ) throws -> ProxyDispatch {
    try withOperation(operationIdentifier) { operation in
      let result = OperationResultMessage.failure(
        reference: operation.reference, failure: failure,
        batchSignatures: operation.batchSignatures)
      do {
        try operation.finishFailure(to: &store, result: result)
      } catch let error as AuthorizationError {
        throw engineLocalError(error)
      }
      return .sendFailure(
        message: .operationResult(result), closeSession: failure.closesSession)
    }
  }

  /// Records one batch signature before the next document is signed.
  internal mutating func recordBatchSignature(
    operationIdentifier: Data, signature: Data, store: inout some JournalStore
  ) throws {
    try withOperation(operationIdentifier) { operation in
      do {
        try operation.recordBatchSignature(to: &store, signature: signature)
      } catch let error as AuthorizationError {
        throw engineLocalError(error)
      }
    }
  }

  /// Completes a batch with exactly the signatures it journaled.
  internal mutating func completeBatch(
    operationIdentifier: Data, store: inout some JournalStore
  ) throws -> ProxyDispatch {
    guard let index = index(of: operationIdentifier) else {
      throw EngineError.unknownLocalOperation
    }
    let result = OperationResultMessage.completed(
      reference: operations[index].reference,
      result: .signatures(operations[index].batchSignatures))
    return try finishCompleted(
      operationIdentifier: operationIdentifier, result: result, store: &store)
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
  /// An operation still awaiting consent is cancelled with nothing sent to
  /// the card; one executing on the card runs to its own conclusion; a
  /// completed result not yet acknowledged stays retained for re-delivery
  /// (section 8.3). Best effort per operation: a record that could not be
  /// written stays at its last persisted state, which recovery resolves.
  internal mutating func sessionClosed(
    store: inout some JournalStore
  ) -> [ProxySessionCloseAction] {
    var actions: [ProxySessionCloseAction] = []
    for index in operations.indices {
      let operationIdentifier = operations[index].reference.operationIdentifier
      switch operations[index].stage {
      case .requested, .awaitingConsent, .executingSafeRead:
        let result = OperationResultMessage.failure(
          reference: operations[index].reference, failure: .cancelled)
        guard (try? operations[index].finishFailure(to: &store, result: result)) != nil
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

  /// Admits a new request, or resolves a reused identifier from the live
  /// table, the journal and the tombstones (section 8.2.2).
  private mutating func receiveRequest(
    _ request: OperationRequest, store: inout some JournalStore
  ) throws -> ProxyDispatch {
    let requestHash: Data
    do {
      requestHash = try request.requestHash()
    } catch {
      throw EngineError.invalidLocalValue
    }
    if let index = index(of: request.operationIdentifier) {
      guard operations[index].requestHash == requestHash else {
        return .send(.error(.duplicateOperation(operationIdentifier: request.operationIdentifier)))
      }
      if let retained = operations[index].retainedResult {
        return .send(.operationResult(retained))
      }
      if operations[index].operationState == .completed {
        return .send(
          .operationResult(
            .retired(
              reference: operations[index].reference, disposition: .completed,
              preservedError: nil)))
      }
      return .ignoredDuplicate(operationIdentifier: request.operationIdentifier)
    }
    if let entry = recovered.first(where: { candidate in
      candidate.record.operationIdentifier == request.operationIdentifier
    }) {
      guard entry.record.requestHash == requestHash else {
        return .send(.error(.duplicateOperation(operationIdentifier: request.operationIdentifier)))
      }
      return .send(.operationResult(Self.answer(for: entry)))
    }
    guard !operations.contains(where: { !$0.operationState.isTerminal }) else {
      return .send(.error(.operationFailed(operationIdentifier: request.operationIdentifier)))
    }
    let transaction: AuthorizationTransaction
    do {
      transaction = try AuthorizationTransaction(request: request)
    } catch {
      throw EngineError.invalidLocalValue
    }
    operations.append(transaction)
    guard grantedProfiles.contains(request.profile) else {
      return try finishFailure(
        operationIdentifier: request.operationIdentifier, failure: .unauthorized, store: &store)
    }
    return .inspectPrerequisites(operationIdentifier: request.operationIdentifier)
  }

  /// A request this endpoint cannot serve is answered, not punished.
  private func receiveRefusal(_ refusal: OperationRequestRefusal) -> ProxyDispatch {
    let result = OperationResultMessage(
      operationIdentifier: refusal.reference.operationIdentifier,
      requestHash: refusal.reference.requestHash,
      status: .rejected,
      error: refusal.error)
    return .send(.operationResult(result))
  }

  /// Retires an acknowledged result, live or re-delivered; any other
  /// acknowledgement is ignored without touching a tombstone (section 8.2.5).
  private mutating func receiveAcknowledgement(
    _ reference: OperationReference, store: inout some JournalStore
  ) throws -> ProxyDispatch {
    let operationIdentifier = reference.operationIdentifier
    if let index = index(of: operationIdentifier) {
      guard operations[index].stage == .resultPending, operations[index].reference == reference
      else { return .notOperation(.operationResultAck(reference)) }
      do {
        try operations[index].acknowledgeResult(to: &store, acknowledgement: reference)
      } catch let error as AuthorizationError {
        throw engineLocalError(error)
      }
      return .resultAcknowledged(operationIdentifier: operationIdentifier)
    }
    guard
      let index = recovered.firstIndex(where: { candidate in
        candidate.record.operationIdentifier == operationIdentifier
      }),
      recovered[index].record.requestHash == reference.requestHash,
      recovered[index].record.state == .deliveryUncertain
    else { return .notOperation(.operationResultAck(reference)) }
    var journal = OperationJournal(recovered: recovered[index].record)
    do {
      try journal.acknowledgeResult(to: &store)
    } catch {
      throw EngineError.persistence
    }
    recovered[index] = RecoveredProxyRecord(record: journal.record, retainedResult: nil)
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

  /// The status report, followed by the result it re-delivers when one is
  /// retained (section 8.3).
  private func statusAnswer(for operationIdentifier: Data) -> ProxyDispatch {
    if let index = index(of: operationIdentifier) {
      let operation = operations[index]
      let report = StatusReport(
        operationIdentifier: operationIdentifier,
        known: true,
        state: operation.operationState,
        requestHash: operation.reference.requestHash,
        retired: operation.operationState == .completed)
      guard let retained = operation.retainedResult else {
        return .send(.operationStatus(report))
      }
      return .sendAll([.operationStatus(report), .operationResult(retained)])
    }
    if let entry = recovered.first(where: { candidate in
      candidate.record.operationIdentifier == operationIdentifier
    }) {
      let report = StatusReport(
        operationIdentifier: operationIdentifier,
        known: true,
        state: entry.record.state,
        requestHash: entry.record.requestHash,
        retired: entry.record.state == .completed)
      guard entry.record.state != .completed else { return .send(.operationStatus(report)) }
      return .sendAll([.operationStatus(report), .operationResult(Self.answer(for: entry))])
    }
    return .send(
      .operationStatus(StatusReport(operationIdentifier: operationIdentifier, known: false)))
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
