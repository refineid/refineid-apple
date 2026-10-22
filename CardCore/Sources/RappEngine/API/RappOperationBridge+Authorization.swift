// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The custodian's steps: the holder's decisions, and the answers a card
/// produced.
extension RappOperationBridge {
  /// The operation has the card and its prerequisite reads are done.
  ///
  /// An action that needs the holder's authorization gives `awaitUserApproval`;
  /// a read skips consent and gives `executeSafeRead` (RAPP v26.10.21 §8.2
  /// items 3 and 6). An operation past its deadline is cancelled instead, with
  /// the result to send. `nowMs` is the continuous clock.
  public func prerequisitesComplete(operationId: RappOperationIdentifier, nowMs: UInt64) throws
    -> RappBridgeAction
  {
    try withProxy { engine in
      try engine.prerequisitesComplete(
        operationIdentifier: operationId, nowMilliseconds: nowMs,
        maximumLifetimeMilliseconds: maximumLifetimeMilliseconds)
    }
  }

  /// Approves exactly the request the consent view rendered.
  public func approve(operationId: RappOperationIdentifier, approvedAtMs: UInt64) throws
    -> RappBridgeAction
  {
    try withProxy { engine in
      guard let request = engine.request(operationId) else { throw RappBindingError.WrongPhase }
      return try engine.approve(
        operationIdentifier: operationId,
        approval: UserApproval(for: request, approvedAtMilliseconds: approvedAtMs),
        nowMilliseconds: approvedAtMs,
        maximumLifetimeMilliseconds: maximumLifetimeMilliseconds)
    }
  }

  /// The holder declined (§8.2 item 3).
  public func deny(operationId: RappOperationIdentifier) throws -> RappBridgeAction {
    try finishFailure(operationId: operationId, failure: .userDenied)
  }

  /// Rejects a request the custodian cannot serve, such as one naming a key
  /// the card does not hold.
  public func requestInvalidOrUnsupported(operationId: RappOperationIdentifier) throws
    -> RappBridgeAction
  {
    try finishFailure(operationId: operationId, failure: .requestInvalidOrUnsupported)
  }

  /// The retry floor refused before any verification: the card reports
  /// fewer than three remaining attempts for the PIN, or none it can read
  /// (§10.2).
  public func retryFloor(operationId: RappOperationIdentifier) throws -> RappBridgeAction {
    try finishFailure(operationId: operationId, failure: .retryFloor)
  }

  /// The card did not answer: no card within the wait, the field lost, a
  /// transmission fault.
  public func cardError(operationId: RappOperationIdentifier) throws -> RappBridgeAction {
    try finishFailure(operationId: operationId, failure: .cardError)
  }

  /// The custodian could not carry the operation out for a reason of its
  /// own.
  public func operationFailed(operationId: RappOperationIdentifier) throws -> RappBridgeAction {
    try finishFailure(operationId: operationId, failure: .operationFailed)
  }

  /// Cancels the live operation if its deadline passed before the card was
  /// commanded (§8.1 item 2); `noAction` when nothing is due. `nowMs` is the
  /// continuous clock.
  public func expireDue(nowMs: UInt64) throws -> RappBridgeAction {
    try locked {
      guard case .proxy(var engine) = side, !closed else { throw RappBindingError.WrongPhase }
      let dispatched: ProxyDispatch?
      do {
        dispatched = try engine.expireDue(
          nowMilliseconds: nowMs, maximumLifetimeMilliseconds: maximumLifetimeMilliseconds)
      } catch {
        throw RappBindingError.WrongPhase
      }
      side = .proxy(engine)
      guard let dispatched else { return .noAction }
      return action(for: dispatched)
    }
  }

  /// Tells the requester which card can answer now (§8.4).
  ///
  /// Call it once right after the session is established and again whenever the
  /// card or its presence changes; a card busy with another session's operation
  /// is present.
  public func reportCardStatus(_ status: RappCardStatus) throws -> RappBridgeAction {
    try locked {
      guard case .proxy = side else { throw RappBindingError.WrongPhase }
      guard !closed else { return .sessionClosed(reason: nil, endedOperation: nil) }
      return send(ProxyOperationEngine.reportCardStatus(status))
    }
  }

  /// Reports a change of the live operation's state (§8.2).
  public func reportProgress(operationId: RappOperationIdentifier, event: ProgressEvent) throws
    -> RappBridgeAction
  {
    try locked {
      guard case .proxy(let engine) = side, !closed else { throw RappBindingError.WrongPhase }
      let message: TypedMessage
      do {
        message = try engine.reportProgress(operationIdentifier: operationId, event: event)
      } catch {
        throw RappBindingError.WrongPhase
      }
      return send(message)
    }
  }

  /// Answers an inspection with the card's answer to reset, or its
  /// historical bytes; empty when the platform exposes neither.
  public func completeInspection(operationId: RappOperationIdentifier, answerToReset: Data) throws
    -> RappBridgeAction
  {
    try complete(operationId: operationId, result: .inspection(answerToReset: answerToReset))
  }

  /// Answers an identity read (§9.1).
  ///
  /// Both dates are `YYYY-MM-DD`; at least one DER certificate travels.
  public func completeIdentity(  // swiftlint:disable:this function_parameter_count
    operationId: RappOperationIdentifier,
    holderName: String,
    cardId: String,
    issuanceDate: String,
    expirationDate: String,
    certificates: [Data]
  ) throws -> RappBridgeAction {
    let identity: CardIdentity
    do {
      identity = try CardIdentity(
        holderName: holderName, cardIdentifier: cardId, issuanceDate: issuanceDate,
        expirationDate: expirationDate, certificates: certificates, tokenDisplayName: nil)
    } catch {
      throw RappBindingError.InvalidInput
    }
    return try complete(operationId: operationId, result: .identity(identity))
  }

  /// Answers a certificate read.
  public func completeCertificate(operationId: RappOperationIdentifier, der: Data) throws
    -> RappBridgeAction
  {
    try complete(operationId: operationId, result: .certificate(der))
  }

  /// Answers a signature.
  public func completeSignature(operationId: RappOperationIdentifier, signature: Data) throws
    -> RappBridgeAction
  {
    try complete(operationId: operationId, result: .signature(signature))
  }

  /// Records one batch signature as the card makes it.
  public func recordBatchSignature(operationId: RappOperationIdentifier, signature: Data) throws {
    try locked {
      guard case .proxy(var engine) = side, !closed else { throw RappBindingError.WrongPhase }
      do {
        try engine.recordBatchSignature(operationIdentifier: operationId, signature: signature)
      } catch {
        throw RappBindingError.WrongPhase
      }
      side = .proxy(engine)
    }
  }

  /// Answers a batch once every document is signed, with exactly those
  /// signatures.
  public func completeBatch(operationId: RappOperationIdentifier) throws -> RappBridgeAction {
    try withProxy { engine in try engine.completeBatch(operationIdentifier: operationId) }
  }

  /// Ends the operation with a result that did not complete.
  private func finishFailure(
    operationId: RappOperationIdentifier, failure: ProxyFailure
  ) throws -> RappBridgeAction {
    try withProxy { engine in
      try engine.finishFailure(operationIdentifier: operationId, failure: failure)
    }
  }

  /// Ends the operation with its completed result.
  private func complete(
    operationId: RappOperationIdentifier, result: CardOperationResult
  ) throws -> RappBridgeAction {
    try withProxy { engine in
      try engine.finishCompleted(
        operationIdentifier: operationId,
        result: .completed(operationIdentifier: operationId, result: result))
    }
  }

  /// Runs one custodian step that produces a dispatch, writing the engine
  /// back.
  private func withProxy(
    _ body: (inout ProxyOperationEngine) throws -> ProxyDispatch
  ) throws -> RappBridgeAction {
    try locked {
      guard case .proxy(var engine) = side, !closed else { throw RappBindingError.WrongPhase }
      let dispatched: ProxyDispatch
      do {
        dispatched = try body(&engine)
      } catch let error as RappBindingError {
        throw error
      } catch {
        throw RappBindingError.WrongPhase
      }
      side = .proxy(engine)
      return action(for: dispatched)
    }
  }
}
