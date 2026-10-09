// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The durable at-most-once coordinator for one operation.
internal struct OperationJournal {
  internal private(set) var record: ProxyJournalRecord

  /// A prepared operation with no transmission behind it.
  internal init(
    pairIdentifier: Data, sessionIdentifier: Data, operationIdentifier: Data, requestHash: Data
  ) {
    self.record = ProxyJournalRecord(
      pairIdentifier: pairIdentifier,
      sessionIdentifier: sessionIdentifier,
      operationIdentifier: operationIdentifier,
      requestHash: requestHash,
      state: .prepared,
      transmissionCount: TransmissionCount.untransmitted,
      automaticRetryPermitted: false,
      batch: nil)
  }

  /// Adopts a record recovered from storage.
  internal init(recovered record: ProxyJournalRecord) {
    self.record = record
  }

  /// Terminal states that need no acknowledgement, unlike a completed result.
  private static func isUnacknowledgedTerminal(_ state: OperationState) -> Bool {
    switch state {
    case .cancelled, .rejected, .credentialRejected, .ambiguous:
      true

    default:
      false
    }
  }

  /// Writes the point of no return before any card command is accepted.
  internal mutating func commit(
    to store: inout some JournalStore, requestHash: Data
  ) throws {
    guard record.state == .prepared else {
      throw JournalError.invalidState(state: record.state)
    }
    guard record.requestHash == requestHash else { throw JournalError.requestHashMismatch }
    try persist(&store, state: .committed, transmissions: TransmissionCount.untransmitted)
  }

  /// Records the single transmission and yields the only value a card adapter
  /// may execute.
  ///
  /// The record reaches storage first. If that write fails nothing is handed
  /// out, so a command can never be transmitted without a durable trace.
  ///
  /// A batch starts its per-document progress in the same write (RAPP
  /// v26.10.1 §8.1): total known, nothing signed yet.
  internal mutating func beginCardCommand<Command>(
    to store: inout some JournalStore, command: Command, batchTotal: Int?
  ) throws -> PendingCardCommand<Command> {
    guard record.state == .committed else {
      throw JournalError.invalidState(state: record.state)
    }
    guard record.transmissionCount == TransmissionCount.untransmitted else {
      throw JournalError.alreadyTransmitted
    }
    var next = record
    next.state = .executing
    next.transmissionCount = TransmissionCount.single
    next.automaticRetryPermitted = false
    next.batch = batchTotal.map { total in
      ProxyJournalRecord.BatchProgress(total: total, completedSignatures: [])
    }
    try store.persist(next)
    record = next
    return PendingCardCommand(command: command)
  }

  /// Records one batch signature before the next document is signed, so a
  /// signature already made is never made again (RAPP v26.10.1 §9.3).
  internal mutating func recordBatchSignature(
    to store: inout some JournalStore, signature: Data
  ) throws {
    guard record.state == .executing, var batch = record.batch,
      batch.completedSignatures.count < batch.total, !signature.isEmpty
    else {
      throw JournalError.invalidState(state: record.state)
    }
    batch.completedSignatures.append(signature)
    var next = record
    next.batch = batch
    try store.persist(next)
    record = next
  }

  /// Writes an unsuccessful terminal state with the result that reports it.
  ///
  /// Legal before any transmission and after the one card exchange; the
  /// retained result answers an identical retransmission later.
  internal mutating func finishFailure(
    to store: inout some JournalStore, state: OperationState, result: OperationResultMessage
  ) throws {
    guard record.state == .prepared || record.state == .executing,
      Self.isUnacknowledgedTerminal(state)
    else {
      throw JournalError.invalidState(state: record.state)
    }
    var next = record
    next.state = state
    next.automaticRetryPermitted = false
    try store.persistResult(next, result: result)
    record = next
  }

  /// Retains a successful consequential result before it may be sent.
  internal mutating func finishCompleted(
    to store: inout some JournalStore, result: OperationResultMessage
  ) throws {
    try persistCompleted(&store, result: result, from: .executing)
  }

  /// Retains a successful safe-read result, which writes no in-flight entry.
  internal mutating func finishSafeReadCompleted(
    to store: inout some JournalStore, result: OperationResultMessage
  ) throws {
    try persistCompleted(&store, result: result, from: .prepared)
  }

  /// Records acknowledgement and releases the retained result, leaving the
  /// durable tombstone (section 8.2.5).
  ///
  /// A result whose delivery became uncertain is still acknowledgeable once
  /// it is delivered again.
  internal mutating func acknowledgeResult(to store: inout some JournalStore) throws {
    guard record.state == .resultPending || record.state == .deliveryUncertain else {
      throw JournalError.invalidState(state: record.state)
    }
    var next = record
    next.state = .completed
    next.automaticRetryPermitted = false
    try store.acknowledgeResult(next)
    record = next
  }

  /// Keeps the result but forbids redelivery or a further card attempt.
  internal mutating func markDeliveryUncertain(to store: inout some JournalStore) throws {
    guard record.state == .resultPending else {
      throw JournalError.invalidState(state: record.state)
    }
    var next = record
    next.state = .deliveryUncertain
    next.automaticRetryPermitted = false
    try store.retainUncertainResult(next)
    record = next
  }

  /// Resolves a record interrupted mid-flight.
  ///
  /// A committed or executing record cannot be proven either way, so it
  /// becomes ambiguous. It is never retried: the card may already have acted.
  internal mutating func recoverAfterCrash(to store: inout some JournalStore) throws {
    guard record.state == .committed || record.state == .executing else {
      throw JournalError.invalidState(state: record.state)
    }
    try persist(&store, state: .ambiguous, transmissions: record.transmissionCount)
  }

  private mutating func persist(
    _ store: inout some JournalStore, state: OperationState, transmissions: UInt8
  ) throws {
    var next = record
    next.state = state
    next.transmissionCount = transmissions
    next.automaticRetryPermitted = false
    try store.persist(next)
    record = next
  }

  private mutating func persistCompleted(
    _ store: inout some JournalStore,
    result: OperationResultMessage,
    from expected: OperationState
  ) throws {
    guard record.state == expected else {
      throw JournalError.invalidState(state: record.state)
    }
    var next = record
    next.state = .resultPending
    next.automaticRetryPermitted = false
    try store.persistResult(next, result: result)
    record = next
  }
}
