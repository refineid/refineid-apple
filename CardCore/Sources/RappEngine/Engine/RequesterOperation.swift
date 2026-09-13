// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One requester-side operation and its durable record.
internal struct RequesterOperation {
  internal let request: OperationRequest

  internal private(set) var record: RequesterJournalRecord

  private let requestHash: Data

  internal var reference: OperationReference {
    OperationReference(
      operationIdentifier: request.operationIdentifier, requestHash: requestHash)
  }

  internal init(request: OperationRequest) throws {
    let hash = try request.requestHash()
    self.request = request
    self.requestHash = hash
    self.record = RequesterJournalRecord(
      pairIdentifier: request.pairIdentifier,
      sessionIdentifier: request.sessionIdentifier,
      operationIdentifier: request.operationIdentifier,
      requestHash: hash,
      state: .idle,
      retainedResult: nil,
      reconciliation: nil)
  }

  /// Which statuses a state may legally receive.
  ///
  /// A completed result is legal only from the state the action actually
  /// reaches: committed for a consequential action, requested for a safe read
  /// that never prepares or commits.
  private static func statusIsLegal(
    _ status: ResultStatus, in state: OperationState, for operation: CardOperation
  ) -> Bool {
    switch status {
    case .completed:
      operation.isConsequential ? state == .committed : state == .requested

    case .denied:
      state == .requested || state == .prepared

    case .cancelled, .rejected, .credentialRejected:
      state == .requested || state == .prepared || state == .committed

    case .ambiguous:
      state == .committed
    }
  }

  /// Writes the intent before the request frame may be released.
  internal mutating func begin(
    to store: inout some RequesterJournalStore
  ) throws -> TypedMessage {
    try require(.idle)
    try persist(&store, state: .requested)
    return .operationRequest(request)
  }

  /// Accepts the proxy's readiness for a consequential action.
  ///
  /// A safe read has no prepare step, so a prepared echo for one is a
  /// violation rather than a surprise.
  internal mutating func receivePrepared(
    _ echo: OperationReference, to store: inout some RequesterJournalStore
  ) throws {
    try require(.requested)
    try requireReference(echo)
    guard request.operation.isConsequential else {
      throw EngineError.authenticatedProtocolViolation(.unexpectedPreparedForSafeRead)
    }
    try persist(&store, state: .prepared)
  }

  /// Accepts an advisory progress notice from the proxy.
  ///
  /// Progress notices never advance or mutate the operation state.
  internal func receiveProgress(_ progress: OperationProgressMessage) throws {
    try requireReference(progress.reference)
    guard !record.state.isTerminal else {
      throw EngineError.authenticatedProtocolViolation(.illegalOperationTransition)
    }
  }

  /// Writes the requester's point of no return before releasing the commit.
  internal mutating func commit(
    to store: inout some RequesterJournalStore
  ) throws -> TypedMessage {
    try require(.prepared)
    try persist(&store, state: .committed)
    return .operationCommit(reference)
  }

  /// Cancels locally, classified by the commit boundary.
  internal mutating func cancel(
    reason: String?, to store: inout some RequesterJournalStore
  ) throws -> RequesterCancelAction {
    let message = TypedMessage.operationCancel(
      CancelMessage(reference: reference, reason: reason))
    switch record.state {
    case .requested, .awaitingConsent, .prepared:
      try forget(&store, state: .cancelled)
      return .terminal(message)

    case .committed, .executing, .resultPending:
      return .advisory(message)

    default:
      throw EngineError.invalidLocalTransition
    }
  }

  /// Applies a proxy cancellation under the same commit boundary.
  internal mutating func receiveCancel(
    _ cancellation: CancelMessage, to store: inout some RequesterJournalStore
  ) throws -> OperationState {
    try requireReference(cancellation.reference)
    switch record.state {
    case .requested, .awaitingConsent, .prepared:
      try forget(&store, state: .cancelled)
      return .cancelled

    case .committed, .executing, .resultPending:
      return record.state

    default:
      throw EngineError.authenticatedProtocolViolation(.illegalOperationTransition)
    }
  }

  /// Validates and retains a result.
  ///
  /// A completed result is held until the acknowledgement is delivered; every
  /// other status is terminal at once and is never acknowledged.
  internal mutating func receiveResult(
    _ result: OperationResultMessage, to store: inout some RequesterJournalStore
  ) throws -> RequesterResultAction {
    do {
      try result.validate(for: reference, operation: request.operation)
    } catch {
      throw EngineError.authenticatedProtocolViolation(.invalidOperationMessage)
    }
    guard Self.statusIsLegal(result.status, in: record.state, for: request.operation) else {
      throw EngineError.authenticatedProtocolViolation(.illegalOperationTransition)
    }
    guard result.status != .completed else {
      record.retainedResult = result.result
      try persist(&store, state: .resultPending)
      return .sendAcknowledgement(.operationResultAck(reference))
    }
    guard let terminal = result.status.failureState, let failure = result.error else {
      throw EngineError.localInvariantFailure
    }
    try forget(&store, state: terminal)
    return .terminal(state: terminal, error: failure)
  }

  /// Records that the acknowledgement was delivered and releases the result.
  ///
  /// Completion removes the journal; only interrupted records stay stored.
  internal mutating func acknowledgementSent(
    to store: inout some RequesterJournalStore
  ) throws -> CardOperationResult {
    try require(.resultPending)
    guard let result = record.retainedResult else {
      throw EngineError.localInvariantFailure
    }
    record.retainedResult = nil
    do {
      try forget(&store, state: .completed)
    } catch {
      record.retainedResult = result
      throw error
    }
    return result
  }

  /// Classifies this operation exactly once when the session closes.
  internal mutating func sessionClosed(
    to store: inout some RequesterJournalStore
  ) throws -> OperationState {
    let terminal: OperationState
    switch record.state {
    case .requested, .awaitingConsent, .prepared:
      terminal = .cancelled

    case .committed, .executing:
      terminal = .ambiguous

    case .resultPending:
      terminal = .deliveryUncertain

    default:
      guard record.state.isTerminal else { throw EngineError.invalidLocalTransition }
      return record.state
    }
    switch terminal {
    case .ambiguous, .deliveryUncertain:
      try persist(&store, state: terminal)

    default:
      try forget(&store, state: terminal)
    }
    return terminal
  }

  /// Stores an authenticated status report as a journal annotation.
  ///
  /// A terminal record keeps the annotation in memory only and is not
  /// re-persisted.
  internal mutating func annotateStatus(
    _ report: StatusReport, to store: inout some RequesterJournalStore
  ) throws {
    if let hash = report.requestHash, hash != requestHash {
      throw EngineError.authenticatedProtocolViolation(.referenceMismatch)
    }
    record.reconciliation = report
    guard !record.state.isTerminal else {
      try? store.remove(operationIdentifier: record.operationIdentifier)
      return
    }
    do {
      try store.persist(record)
    } catch {
      throw EngineError.persistence
    }
  }

  /// Moves to a terminal state while deleting the journal.
  ///
  /// A failed removal rolls the state back so recovery retries it.
  private mutating func forget(
    _ store: inout some RequesterJournalStore, state: OperationState
  ) throws {
    precondition(state.isTerminal)
    let previous = record.state
    record.state = state
    do {
      try store.remove(operationIdentifier: record.operationIdentifier)
    } catch {
      record.state = previous
      throw EngineError.persistence
    }
  }

  private func require(_ expected: OperationState) throws {
    guard record.state == expected else { throw EngineError.invalidLocalTransition }
  }

  private func requireReference(_ echo: OperationReference) throws {
    guard echo == reference else {
      throw EngineError.authenticatedProtocolViolation(.referenceMismatch)
    }
  }

  private mutating func persist(
    _ store: inout some RequesterJournalStore, state: OperationState
  ) throws {
    let previous = record.state
    record.state = state
    do {
      try store.persist(record)
    } catch {
      record.state = previous
      throw EngineError.persistence
    }
  }
}
