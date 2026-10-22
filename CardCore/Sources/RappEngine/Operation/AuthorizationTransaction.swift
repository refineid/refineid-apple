// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One operation of a session from admission to its result (RAPP v26.10.22
/// §8).
///
/// It lives in memory only and ends with the session.
internal struct AuthorizationTransaction {
  /// The request as admitted; the PIN prompt renders from this snapshot
  /// (§8.2 item 3).
  internal let request: OperationRequest

  internal private(set) var stage: AuthorizationStage

  /// The signatures a batch has made so far, in document order; empty for
  /// every other operation.
  internal private(set) var batchSignatures: [Data]

  internal var operationIdentifier: RappOperationIdentifier { request.operationIdentifier }

  /// Whether the operation has its result.
  internal var isTerminal: Bool { stage == .terminal }

  /// Admits a request.
  internal init(request: OperationRequest) {
    self.request = request
    self.stage = .requested
    self.batchSignatures = []
  }

  /// Records that the operation has the card and its prerequisite reads are
  /// done.
  ///
  /// An action that needs a PIN waits for it; a read asks the holder nothing
  /// and runs (§8.2 items 3 and 6).
  internal mutating func prerequisitesComplete() throws -> PrerequisitesOutcome {
    guard stage == .requested else { throw AuthorizationError.wrongStage(stage: stage) }
    guard request.operation.isConsequential else {
      stage = .executingSafeRead
      return .executeSafeRead(AuthorizedSafeRead(operation: request.operation))
    }
    stage = .awaitingConsent
    return .awaitConsent
  }

  /// Accepts the holder's approval and hands out the one card command.
  internal mutating func approve(
    _ approval: UserApproval,
    nowMilliseconds: UInt64,
    maximumLifetimeMilliseconds: UInt64
  ) throws -> PendingCardCommand<AuthorizedCardCommand> {
    guard stage == .awaitingConsent else { throw AuthorizationError.wrongStage(stage: stage) }
    guard approval.operationIdentifier == request.operationIdentifier else {
      throw AuthorizationError.approvalMismatch
    }
    let deadline: UInt64
    do {
      deadline = try request.localDeadlineMilliseconds(
        maximumLifetimeMilliseconds: maximumLifetimeMilliseconds)
    } catch {
      throw AuthorizationError.expired
    }
    guard approval.approvedAtMilliseconds >= request.localStartMilliseconds,
      approval.approvedAtMilliseconds <= deadline, nowMilliseconds <= deadline
    else { throw AuthorizationError.expired }
    stage = .executing
    return PendingCardCommand(command: AuthorizedCardCommand(operation: request.operation))
  }

  /// Ends the operation with a result that did not complete.
  internal mutating func finishFailure(_ result: OperationResultMessage) throws {
    guard !isTerminal else { throw AuthorizationError.wrongStage(stage: stage) }
    guard result.status != .completed else { throw AuthorizationError.invalidResult }
    do {
      try result.validate(for: request.operationIdentifier, operation: request.operation)
    } catch {
      throw AuthorizationError.invalidResult
    }
    stage = .terminal
  }

  /// Ends the operation with its completed result.
  ///
  /// A batch completes only with exactly the signatures it recorded, one per
  /// document.
  internal mutating func finishCompleted(_ result: OperationResultMessage) throws {
    guard stage == .executing || stage == .executingSafeRead else {
      throw AuthorizationError.wrongStage(stage: stage)
    }
    guard result.status == .completed else { throw AuthorizationError.invalidResult }
    do {
      try result.validate(for: request.operationIdentifier, operation: request.operation)
    } catch {
      throw AuthorizationError.invalidResult
    }
    if let total = request.operation.batchTotal {
      guard batchSignatures.count == total,
        (try? result.typedResult(for: request.operation)) == .signatures(batchSignatures)
      else { throw AuthorizationError.invalidResult }
    }
    stage = .terminal
  }

  /// Records one batch signature as the card makes it.
  internal mutating func recordBatchSignature(_ signature: Data) throws {
    guard stage == .executing else { throw AuthorizationError.wrongStage(stage: stage) }
    guard let total = request.operation.batchTotal, batchSignatures.count < total,
      !signature.isEmpty
    else { throw AuthorizationError.invalidResult }
    batchSignatures.append(signature)
  }

  /// Whether the request's local deadline has passed (§8.1 item 2).
  internal func isExpired(nowMilliseconds: UInt64, maximumLifetimeMilliseconds: UInt64) -> Bool {
    guard
      let deadline = try? request.localDeadlineMilliseconds(
        maximumLifetimeMilliseconds: maximumLifetimeMilliseconds)
    else { return false }
    return nowMilliseconds > deadline
  }
}
