// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One operation from validated request to durable terminal state.
///
/// The stage is authoritative before approval; afterwards the journal is,
/// because only the journal survives a restart. Approval of a consequential
/// action writes the in-flight entry before the card command exists
/// (RAPP v26.10.9 §8.1).
internal struct AuthorizationTransaction {
  internal let request: OperationRequest

  internal let requestHash: Data

  internal private(set) var journal: OperationJournal

  internal private(set) var stage: AuthorizationStage

  internal private(set) var retainedResult: OperationResultMessage?

  internal var reference: OperationReference {
    OperationReference(
      operationIdentifier: request.operationIdentifier, requestHash: requestHash)
  }

  /// The signatures a batch has made so far, in document order.
  internal var batchSignatures: [Data] {
    journal.record.batch?.completedSignatures ?? []
  }

  /// The state the protocol shows for this operation.
  internal var operationState: OperationState {
    switch stage {
    case .requested:
      .requested

    case .awaitingConsent, .executingSafeRead:
      .awaitingConsent

    case .executing:
      .executing

    case .resultPending:
      .resultPending

    case .terminal:
      journal.record.state
    }
  }

  /// Prepares an operation, persisting and transmitting nothing.
  internal init(request: OperationRequest) throws {
    let hash = try request.requestHash()
    self.request = request
    self.requestHash = hash
    self.journal = OperationJournal(
      pairIdentifier: request.pairIdentifier,
      sessionIdentifier: request.sessionIdentifier,
      operationIdentifier: request.operationIdentifier,
      requestHash: hash)
    self.stage = .requested
    self.retainedResult = nil
  }

  /// Records that the profile's bounded reads finished.
  ///
  /// Consent is not asked
  /// before this point.
  internal mutating func prerequisitesComplete() throws {
    guard stage == .requested else { throw AuthorizationError.wrongStage(stage: stage) }
    stage = .awaitingConsent
  }

  /// Accepts the holder's consent for this exact request.
  ///
  /// A consequential action writes the durable in-flight entry before the
  /// card command is handed out; if that write fails no command exists.
  internal mutating func approve(
    _ approval: UserApproval,
    to store: inout some JournalStore,
    nowMilliseconds: UInt64,
    maximumLifetimeMilliseconds: UInt64
  ) throws -> ApprovalOutcome {
    guard stage == .awaitingConsent else { throw AuthorizationError.wrongStage(stage: stage) }
    try validate(
      approval, nowMilliseconds: nowMilliseconds,
      maximumLifetimeMilliseconds: maximumLifetimeMilliseconds)
    guard request.operation.isConsequential else {
      stage = .executingSafeRead
      return .executeSafeRead(AuthorizedSafeRead(operation: request.operation))
    }
    let command = AuthorizedCardCommand(operation: request.operation)
    do {
      _ = try journal.beginCardCommand(
        to: &store, requestHash: requestHash, command: command,
        batchTotal: request.operation.batchTotal)
    } catch let error as JournalError {
      throw AuthorizationError.journal(error)
    }
    stage = .executing
    return .executeCardCommand
  }

  /// Records one batch signature as the card makes it.
  internal mutating func recordBatchSignature(
    to store: inout some JournalStore, signature: Data
  ) throws {
    guard stage == .executing else { throw AuthorizationError.wrongStage(stage: stage) }
    try mapJournal { try journal.recordBatchSignature(to: &store, signature: signature) }
  }

  /// Retains a completed result before it may be released to the transport.
  internal mutating func finishCompleted(
    to store: inout some JournalStore, result: OperationResultMessage
  ) throws {
    guard result.status == .completed else { throw AuthorizationError.invalidResult }
    do {
      try result.validate(for: reference, operation: request.operation)
    } catch {
      throw AuthorizationError.invalidResult
    }
    if let batch = journal.record.batch {
      // A batch completes only with exactly the signatures it journaled.
      guard batch.completedSignatures.count == batch.total,
        (try? result.typedResult(for: request.operation))
          == .signatures(batch.completedSignatures)
      else { throw AuthorizationError.invalidResult }
    }
    switch stage {
    case .executing:
      try mapJournal { try journal.finishCompleted(to: &store, result: result) }

    case .executingSafeRead:
      try mapJournal { try journal.finishSafeReadCompleted(to: &store, result: result) }

    default:
      throw AuthorizationError.wrongStage(stage: stage)
    }
    retainedResult = result
    stage = .resultPending
  }

  /// Records a stable non-successful result from any legal stage, keeping
  /// the result so an identical retransmission is answered without the card.
  internal mutating func finishFailure(
    to store: inout some JournalStore, result: OperationResultMessage
  ) throws {
    guard result.status != .completed else { throw AuthorizationError.invalidResult }
    do {
      try result.validate(for: reference, operation: request.operation)
    } catch {
      throw AuthorizationError.invalidResult
    }
    guard let terminal = result.status.failureState else {
      throw AuthorizationError.invalidResult
    }
    switch stage {
    case .requested, .awaitingConsent, .executingSafeRead, .executing:
      try mapJournal { try journal.finishFailure(to: &store, state: terminal, result: result) }

    default:
      throw AuthorizationError.wrongStage(stage: stage)
    }
    retainedResult = result
    stage = .terminal
  }

  /// Records the acknowledgement that releases the retained result.
  internal mutating func acknowledgeResult(
    to store: inout some JournalStore, acknowledgement: OperationReference
  ) throws {
    guard stage == .resultPending else { throw AuthorizationError.wrongStage(stage: stage) }
    guard acknowledgement == reference else { throw AuthorizationError.referenceMismatch }
    try mapJournal { try journal.acknowledgeResult(to: &store) }
    retainedResult = nil
    stage = .terminal
  }

  /// Records that the session was lost after the result was sent.
  ///
  /// The result stays retained so it can be delivered again on request, but
  /// no automatic replay of the command or the result follows.
  internal mutating func deliveryBecameUncertain(
    to store: inout some JournalStore
  ) throws {
    guard stage == .resultPending else { throw AuthorizationError.wrongStage(stage: stage) }
    try mapJournal { try journal.markDeliveryUncertain(to: &store) }
    stage = .terminal
  }

  /// Resolves a record that a restart interrupted, without retrying it.
  internal mutating func recoverAfterCrash(to store: inout some JournalStore) throws {
    try mapJournal { try journal.recoverAfterCrash(to: &store) }
    stage = .terminal
  }

  private func deadlineMilliseconds(_ maximumLifetimeMilliseconds: UInt64) throws -> UInt64 {
    do {
      return try request.localDeadlineMilliseconds(
        maximumLifetimeMilliseconds: maximumLifetimeMilliseconds)
    } catch {
      throw AuthorizationError.expired
    }
  }

  private func validate(
    _ approval: UserApproval,
    nowMilliseconds: UInt64,
    maximumLifetimeMilliseconds: UInt64
  ) throws {
    guard approval.operationIdentifier == request.operationIdentifier,
      approval.requestHash == requestHash
    else { throw AuthorizationError.approvalMismatch }
    let deadline = try deadlineMilliseconds(maximumLifetimeMilliseconds)
    guard approval.approvedAtMilliseconds >= request.localStartMilliseconds,
      approval.approvedAtMilliseconds <= deadline,
      nowMilliseconds <= deadline
    else { throw AuthorizationError.expired }
  }

  private func mapJournal<Answer>(_ body: () throws -> Answer) throws -> Answer {
    do {
      return try body()
    } catch let error as JournalError {
      throw AuthorizationError.journal(error)
    }
  }
}
