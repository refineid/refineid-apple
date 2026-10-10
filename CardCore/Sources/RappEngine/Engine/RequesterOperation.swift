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

  /// The terminal state an unanswered request reaches when its session ends.
  ///
  /// The custodian may have acted on a consequential request after consent,
  /// so its fate is ambiguous until reconciled (section 8.3); a safe read
  /// touched no credential and simply ends.
  private var unansweredTerminal: OperationState {
    request.operation.isConsequential ? .ambiguous : .cancelled
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

  /// Writes the intent before the request frame may be released.
  internal mutating func begin(
    to store: inout some RequesterJournalStore
  ) throws -> TypedMessage {
    try require(.idle)
    try persist(&store, state: .requested)
    return .operationRequest(request)
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

  /// Abandons the request locally; no message travels (section 8.3).
  internal mutating func cancel(to store: inout some RequesterJournalStore) throws
    -> OperationState
  {
    guard record.state == .requested else { throw EngineError.invalidLocalTransition }
    let terminal = unansweredTerminal
    if terminal == .ambiguous {
      try persist(&store, state: terminal)
    } else {
      try forget(&store, state: terminal)
    }
    return terminal
  }

  /// Validates and retains a result.
  ///
  /// A completed result is held until the acknowledgement is delivered; every
  /// other status, and a retired completed one, is terminal at once and is
  /// never acknowledged.
  internal mutating func receiveResult(
    _ result: OperationResultMessage, to store: inout some RequesterJournalStore
  ) throws -> RequesterResultAction {
    do {
      try result.validate(for: reference, operation: request.operation)
    } catch {
      throw EngineError.authenticatedProtocolViolation(.invalidOperationMessage)
    }
    guard record.state == .requested else {
      throw EngineError.authenticatedProtocolViolation(.illegalOperationTransition)
    }
    if result.status == .completed, !result.retired {
      do {
        record.retainedResult = try result.typedResult(for: request.operation)
      } catch {
        throw EngineError.authenticatedProtocolViolation(.invalidOperationMessage)
      }
      try persist(&store, state: .resultPending)
      return .sendAcknowledgement(.operationResultAck(reference))
    }
    let terminal = result.status.failureState ?? .completed
    let partial: [Data]
    do {
      partial = try result.partialSignatures(for: request.operation)
    } catch {
      throw EngineError.authenticatedProtocolViolation(.invalidOperationMessage)
    }
    try forget(&store, state: terminal)
    return .terminal(
      state: terminal, status: result.status, error: result.error, batchSignatures: partial)
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
    case .requested:
      terminal = unansweredTerminal

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
