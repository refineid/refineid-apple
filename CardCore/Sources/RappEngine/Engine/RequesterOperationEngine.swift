// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Every live and terminal requester operation for one paired endpoint.
///
/// Terminal entries stay addressable so an authenticated status report can
/// still annotate them after the fact.
internal struct RequesterOperationEngine {
  private var operations: [RequesterOperation]

  private var recovered: [RequesterJournalRecord]

  internal var liveOperationStates: [Data: OperationState] {
    var states: [Data: OperationState] = [:]
    for operation in operations {
      states[operation.record.operationIdentifier] = operation.record.state
    }
    return states
  }

  internal init(recovered: [RequesterJournalRecord]) {
    self.operations = []
    self.recovered = recovered
  }

  private static func stale(_ operationIdentifier: Data) -> RequesterDispatch {
    .ignoredStale(
      operationIdentifier: operationIdentifier,
      response: .error(.unknownOperation(operationIdentifier: operationIdentifier)))
  }

  /// A peer error carries no operation state, so it classifies directly.
  private static func errorDispatch(_ error: ProtocolErrorMessage) -> RequesterDispatch {
    switch error {
    case .busy:
      .peerBusy

    case .unknownOperation(let operationIdentifier):
      .peerUnknownOperation(operationIdentifier: operationIdentifier)
    }
  }

  /// Writes a unique operation before its request frame is released.
  internal mutating func begin(
    _ request: OperationRequest, store: inout some RequesterJournalStore
  ) throws -> TypedMessage {
    guard !contains(request.operationIdentifier) else {
      throw EngineError.duplicateLocalOperationIdentifier
    }
    var operation: RequesterOperation
    do {
      operation = try RequesterOperation(request: request)
    } catch {
      throw EngineError.invalidLocalValue
    }
    let message = try operation.begin(to: &store)
    operations.append(operation)
    return message
  }

  /// Writes the commit before releasing the commit message.
  internal mutating func commit(
    operationIdentifier: Data, store: inout some RequesterJournalStore
  ) throws -> TypedMessage {
    try withOperation(operationIdentifier) { try $0.commit(to: &store) }
  }

  /// Cancels locally and returns the exact message to release.
  internal mutating func cancel(
    operationIdentifier: Data,
    reason: String?,
    store: inout some RequesterJournalStore
  ) throws -> RequesterCancelAction {
    try withOperation(operationIdentifier) { try $0.cancel(reason: reason, to: &store) }
  }

  /// Classifies one authenticated inbound message.
  internal mutating func receive(
    _ message: TypedMessage, store: inout some RequesterJournalStore
  ) throws -> RequesterDispatch {
    if case .operationStatus(let report) = message {
      return try receiveStatus(report, store: &store)
    }
    if case .error(let error) = message {
      return Self.errorDispatch(error)
    }
    guard let operationIdentifier = message.referencedOperationIdentifier else {
      return .notOperation(message)
    }
    guard let index = index(of: operationIdentifier),
      !operations[index].record.state.isTerminal
    else { return Self.stale(operationIdentifier) }

    return try receiveActiveOperation(
      message, index: index, operationIdentifier: operationIdentifier, store: &store)
  }

  private mutating func receiveActiveOperation(
    _ message: TypedMessage,
    index: Int,
    operationIdentifier: Data,
    store: inout some RequesterJournalStore
  ) throws -> RequesterDispatch {
    switch message {
    case .operationPrepared(let reference):
      try operations[index].receivePrepared(reference, to: &store)
      return .prepared(operationIdentifier: operationIdentifier)

    case .operationProgress(let progress):
      try operations[index].receiveProgress(progress)
      return .progress(operationIdentifier: operationIdentifier, event: progress.event)

    case .operationResult(let result):
      let action = try operations[index].receiveResult(result, to: &store)
      return switch action {
      case .sendAcknowledgement(let message):
        .sendResultAcknowledgement(operationIdentifier: operationIdentifier, message: message)

      case .terminal(let state, let failure):
        .terminal(operationIdentifier: operationIdentifier, state: state, reason: failure)
      }

    case .operationCancel(let cancellation):
      let state = try operations[index].receiveCancel(cancellation, to: &store)
      return .cancellationReceived(operationIdentifier: operationIdentifier, state: state)

    default:
      throw EngineError.authenticatedProtocolViolation(.illegalMessageForActiveOperation)
    }
  }

  /// Records that the acknowledgement went out and releases the result.
  internal mutating func acknowledgementReleased(
    operationIdentifier: Data, store: inout some RequesterJournalStore
  ) throws -> CardOperationResult {
    try withOperation(operationIdentifier) { try $0.acknowledgementSent(to: &store) }
  }

  /// Classifies every live operation when the session closes.
  ///
  /// Best effort per operation: one record's failed terminal write must
  /// not leave the rest unclassified, and a record that could not be
  /// written stays at its last persisted state, which recovery resolves
  /// the next time this pairing begins operations.
  internal mutating func sessionClosed(
    store: inout some RequesterJournalStore
  ) -> [(operationIdentifier: Data, state: OperationState)] {
    var classified: [(operationIdentifier: Data, state: OperationState)] = []
    for index in operations.indices where !operations[index].record.state.isTerminal {
      let operationIdentifier = operations[index].record.operationIdentifier
      guard let state = try? operations[index].sessionClosed(to: &store) else { continue }
      classified.append((operationIdentifier, state))
    }
    return classified
  }

  private mutating func receiveStatus(
    _ report: StatusReport, store: inout some RequesterJournalStore
  ) throws -> RequesterDispatch {
    let operationIdentifier = report.operationIdentifier
    if let index = index(of: operationIdentifier) {
      try operations[index].annotateStatus(report, to: &store)
    } else if let index = recovered.firstIndex(where: { candidate in
      candidate.operationIdentifier == operationIdentifier
    }) {
      if let hash = report.requestHash, hash != recovered[index].requestHash {
        throw EngineError.authenticatedProtocolViolation(.referenceMismatch)
      }
      recovered[index].reconciliation = report
      do {
        if recovered[index].state.isTerminal {
          try store.remove(operationIdentifier: operationIdentifier)
        } else {
          try store.persist(recovered[index])
        }
      } catch {
        throw EngineError.persistence
      }
    } else {
      return Self.stale(operationIdentifier)
    }
    return .statusAnnotated(operationIdentifier: operationIdentifier)
  }

  private mutating func withOperation<Answer>(
    _ operationIdentifier: Data, _ body: (inout RequesterOperation) throws -> Answer
  ) throws -> Answer {
    guard let index = index(of: operationIdentifier) else {
      throw EngineError.unknownLocalOperation
    }
    return try body(&operations[index])
  }

  private func index(of operationIdentifier: Data) -> Int? {
    operations.firstIndex { $0.record.operationIdentifier == operationIdentifier }
  }

  private func contains(_ operationIdentifier: Data) -> Bool {
    index(of: operationIdentifier) != nil
      || recovered.contains { $0.operationIdentifier == operationIdentifier }
  }
}
