// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

/// 3. At-most-once card safety (RAPP v26.10.1 §8.1)
internal func step3() throws {
  // MARK: - 3. At-most-once card safety
  try approvalDurableBeforeTransmission()
  try secondTransmissionRefused()
  try failedWriteHandsOutNothing()
  try ambiguousCompletionTerminal()
  try cancelBeforeConsent()
}

/// Approval writes the in-flight entry before anything reaches the card.
private func approvalDurableBeforeTransmission() throws {
  var store = OperationJournalStore()
  var transaction = try AuthorizationTransaction(request: try browserRequest())
  try executeToCard(&transaction, &store)

  let states = store.writes.map(\.state)
  check(
    "the untransmitted entry is durable before the transmission is",
    states == [.committed, .executing])
  check(
    "the transmission is recorded before the command is taken",
    store.writes.last?.transmissionCount == TransmissionCount.single)
  check("the operation is executing", transaction.stage == .executing)
  check("exactly one transmission is recorded", store.recordedTransmissions == 1)
}

/// A second approval, and a second journal transmission, are refused.
private func secondTransmissionRefused() throws {
  var store = OperationJournalStore()
  var transaction = try AuthorizationTransaction(request: try browserRequest())
  try executeToCard(&transaction, &store)

  var second = false
  do {
    let approval = try UserApproval(
      for: transaction.request, approvedAtMilliseconds: OperationFixture.approvalMilliseconds)
    _ = try transaction.approve(
      approval, to: &store, nowMilliseconds: OperationFixture.approvalMilliseconds,
      maximumLifetimeMilliseconds: OperationFixture.maximumLifetimeMilliseconds)
    second = true
  } catch AuthorizationError.wrongStage {
    second = false
  }
  check("a second approval after execution began is refused", !second)

  // The journal refuses a second transmission even when driven directly.
  var journal = OperationJournal(
    pairIdentifier: OperationFixture.pairIdentifier,
    sessionIdentifier: OperationFixture.sessionIdentifier,
    operationIdentifier: OperationFixture.operationIdentifier,
    requestHash: try browserRequest().requestHash())
  var direct = OperationJournalStore()
  try journal.commit(to: &direct, requestHash: try browserRequest().requestHash())
  let first = try journal.beginCardCommand(to: &direct, command: "one-shot")
  _ = first.execute { $0 }
  var journalSecond = false
  do {
    _ = try journal.beginCardCommand(to: &direct, command: "one-shot")
    journalSecond = true
  } catch JournalError.invalidState {
    journalSecond = false
  }
  check("the journal refuses a second transmission", !journalSecond)
}

/// A durable write that fails dispatches nothing (section 8.2.4).
private func failedWriteHandsOutNothing() throws {
  var store = OperationJournalStore()
  var transaction = try AuthorizationTransaction(request: try browserRequest())
  try transaction.prerequisitesComplete()
  let approval = try UserApproval(
    for: transaction.request, approvedAtMilliseconds: OperationFixture.approvalMilliseconds)
  store.failNextWrite = true
  var dispatched = false
  do {
    _ = try transaction.approve(
      approval, to: &store, nowMilliseconds: OperationFixture.approvalMilliseconds,
      maximumLifetimeMilliseconds: OperationFixture.maximumLifetimeMilliseconds)
    dispatched = true
  } catch AuthorizationError.journal(.persistence) {
    dispatched = false
  }
  check("a failed durable write dispatches no command", !dispatched)
  check("no transmission is recorded after a failed write", store.recordedTransmissions == 0)
  check("the operation is not executing", transaction.stage != .executing)
}

/// An ambiguous completion is reported, never retried.
private func ambiguousCompletionTerminal() throws {
  var store = OperationJournalStore()
  var transaction = try AuthorizationTransaction(request: try browserRequest())
  try executeToCard(&transaction, &store)

  let ambiguous = OperationResultMessage.failure(
    reference: transaction.reference, failure: .cardCompletionAmbiguous)
  try transaction.finishFailure(to: &store, result: ambiguous)
  check("an ambiguous completion is terminal", transaction.operationState == .ambiguous)
  check(
    "an ambiguous record forbids automatic retry",
    store.writes.last?.automaticRetryPermitted == false)
  check(
    "the ambiguous record keeps its transmission count",
    store.writes.last?.transmissionCount == TransmissionCount.single)
  check(
    "the ambiguous result is retained for an identical retransmission",
    store.retained[OperationFixture.operationIdentifier] == ambiguous)

  var retried = false
  do {
    let approval = try UserApproval(
      for: transaction.request, approvedAtMilliseconds: OperationFixture.approvalMilliseconds)
    _ = try transaction.approve(
      approval, to: &store, nowMilliseconds: OperationFixture.approvalMilliseconds,
      maximumLifetimeMilliseconds: OperationFixture.maximumLifetimeMilliseconds)
    retried = true
  } catch AuthorizationError.wrongStage {
    retried = false
  }
  check("an ambiguous operation cannot be retried", !retried)
}

/// A session lost before consent cancels with nothing sent to the card.
private func cancelBeforeConsent() throws {
  var store = OperationJournalStore()
  var transaction = try AuthorizationTransaction(request: try browserRequest())
  try transaction.prerequisitesComplete()
  let cancelled = OperationResultMessage.failure(
    reference: transaction.reference, failure: .cancelled)
  try transaction.finishFailure(to: &store, result: cancelled)
  check("the operation is cancelled", transaction.operationState == .cancelled)
  check("the cancelled record shows no transmission", store.recordedTransmissions == 0)
  check("the cancellation names the expiry error", cancelled.error == .operationExpired)
}

/// 6. Journal recovery and result redelivery
internal func step6() throws {
  // MARK: - 6. Journal recovery and result redelivery
  try interruptedRecoveryAmbiguous()
  try retainedResultUntilAcknowledged()
  try acknowledgementEchoesOperation()
  try safeReadDirect()
  try approvalDeadlineEnforced()
}

/// An interrupted operation recovers as ambiguous, never as retryable.
private func interruptedRecoveryAmbiguous() throws {
  var store = OperationJournalStore()
  var transaction = try AuthorizationTransaction(request: try browserRequest())
  try executeToCard(&transaction, &store)

  let interrupted = try #require(store.writes.last, "an interrupted record exists")
  var recovered = OperationJournal(recovered: interrupted)
  var afterRestart = OperationJournalStore()
  try recovered.recoverAfterCrash(to: &afterRestart)
  check("an interrupted operation recovers as ambiguous", recovered.record.state == .ambiguous)
  check(
    "a recovered operation is never retryable",
    recovered.record.automaticRetryPermitted == false)
  check(
    "recovery keeps the transmission it may have made",
    recovered.record.transmissionCount == TransmissionCount.single)

  // An in-flight entry written before the transmission is equally
  // ambiguous: the entry alone does not prove the card was left untouched.
  var committedOnly = OperationJournal(
    pairIdentifier: OperationFixture.pairIdentifier,
    sessionIdentifier: OperationFixture.sessionIdentifier,
    operationIdentifier: OperationFixture.operationIdentifier,
    requestHash: try browserRequest().requestHash())
  var committedStore = OperationJournalStore()
  try committedOnly.commit(
    to: &committedStore, requestHash: try browserRequest().requestHash())
  try committedOnly.recoverAfterCrash(to: &committedStore)
  check(
    "an untransmitted in-flight entry recovers as ambiguous",
    committedOnly.record.state == .ambiguous)

  var terminalRecovery = false
  do {
    try committedOnly.recoverAfterCrash(to: &committedStore)
    terminalRecovery = true
  } catch JournalError.invalidState {
    terminalRecovery = false
  }
  check("a terminal record is not recovered again", !terminalRecovery)
}

/// A retained result stays available until it is acknowledged.
private func retainedResultUntilAcknowledged() throws {
  var store = OperationJournalStore()
  var transaction = try AuthorizationTransaction(request: try browserRequest())
  try executeToCard(&transaction, &store)
  let completed = OperationResultMessage.completed(
    reference: transaction.reference, result: .signature(OperationFixture.signature))
  try transaction.finishCompleted(to: &store, result: completed)

  check("a completed result is retained", transaction.retainedResult == completed)
  check(
    "the retained result is durable",
    store.retained[OperationFixture.operationIdentifier] == completed)
  check("the operation awaits acknowledgement", transaction.operationState == .resultPending)

  // Losing the session keeps the result for re-delivery, never a replay.
  var uncertain = transaction
  var uncertainStore = store
  try uncertain.deliveryBecameUncertain(to: &uncertainStore)
  check(
    "an uncertain delivery keeps the result", uncertain.operationState == .deliveryUncertain)
  check("the result survives an uncertain delivery", uncertainStore.uncertain == 1)
  check(
    "an uncertain delivery forbids automatic retry",
    uncertainStore.writes.last?.automaticRetryPermitted == false)
}

/// An acknowledgement must echo the operation it acknowledges.
private func acknowledgementEchoesOperation() throws {
  var store = OperationJournalStore()
  var transaction = try AuthorizationTransaction(request: try browserRequest())
  try executeToCard(&transaction, &store)
  let completed = OperationResultMessage.completed(
    reference: transaction.reference, result: .signature(OperationFixture.signature))
  try transaction.finishCompleted(to: &store, result: completed)

  var wrongAck = false
  do {
    try transaction.acknowledgeResult(
      to: &store,
      acknowledgement: OperationReference(
        operationIdentifier: OperationFixture.otherOperation,
        requestHash: transaction.reference.requestHash))
    wrongAck = true
  } catch AuthorizationError.referenceMismatch {
    wrongAck = false
  }
  check("an acknowledgement for another operation is refused", !wrongAck)

  try transaction.acknowledgeResult(to: &store, acknowledgement: transaction.reference)
  check("acknowledgement retires the operation", transaction.operationState == .completed)
  check("acknowledgement releases the retained result", transaction.retainedResult == nil)
  check(
    "the durable result is erased and only the tombstone stays",
    store.retained[OperationFixture.operationIdentifier] == nil
      && store.writes.last?.state == .completed)
}

/// A safe read answers directly, with no in-flight entry or transmission.
private func safeReadDirect() throws {
  var store = OperationJournalStore()
  var transaction = try AuthorizationTransaction(request: try identityRequest())
  try transaction.prerequisitesComplete()
  let approval = try UserApproval(
    for: transaction.request, approvedAtMilliseconds: OperationFixture.approvalMilliseconds)
  let outcome = try transaction.approve(
    approval, to: &store, nowMilliseconds: OperationFixture.approvalMilliseconds,
    maximumLifetimeMilliseconds: OperationFixture.maximumLifetimeMilliseconds)
  check(
    "a safe read executes without an in-flight entry",
    outcome == .executeSafeRead(AuthorizedSafeRead(operation: .readIdentity))
      && store.writes.isEmpty)

  let result = OperationResultMessage.completed(
    reference: transaction.reference,
    result: .identity(
      CardIdentity(
        holderName: "Holder", cardIdentifier: "identifier", issuanceDate: "2026-01-01",
        expirationDate: "2031-01-01", certificates: [OperationFixture.certificate],
        tokenDisplayName: nil)))
  try transaction.finishCompleted(to: &store, result: result)
  check("a safe read records no transmission", store.recordedTransmissions == 0)
  try transaction.acknowledgeResult(to: &store, acknowledgement: transaction.reference)
  check("a safe read completes on acknowledgement", transaction.operationState == .completed)
}

/// An approval after the local deadline authorizes nothing and writes nothing.
private func approvalDeadlineEnforced() throws {
  var store = OperationJournalStore()
  var transaction = try AuthorizationTransaction(request: try browserRequest())
  try transaction.prerequisitesComplete()
  let deadline = try transaction.request.localDeadlineMilliseconds(
    maximumLifetimeMilliseconds: OperationFixture.maximumLifetimeMilliseconds)
  let late = try UserApproval(for: transaction.request, approvedAtMilliseconds: deadline + 1)
  var expired = false
  do {
    _ = try transaction.approve(
      late, to: &store, nowMilliseconds: deadline + 1,
      maximumLifetimeMilliseconds: OperationFixture.maximumLifetimeMilliseconds)
  } catch AuthorizationError.expired {
    expired = true
  }
  check("an approval after the deadline is refused", expired)
  check("an expired approval writes nothing", store.writes.isEmpty)
}
