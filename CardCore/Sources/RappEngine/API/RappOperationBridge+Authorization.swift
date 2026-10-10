// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

// The inspection answer names one parameter per value the card reported.
// swiftlint:disable function_parameter_count

/// The holder's decisions, and the answers a card produced.
extension RappOperationBridge {
  /// Records that the profile's bounded reads finished.
  public func prerequisitesComplete(operationId: Data) throws -> RappBridgeAction {
    try locked {
      guard case .proxy(var engine) = side else { throw RappBindingError.WrongPhase }
      defer { side = .proxy(engine) }
      try mapping { try engine.prerequisitesComplete(operationIdentifier: operationId) }
      guard let operation = engine.operation(operationId) else {
        throw RappBindingError.WrongPhase
      }
      return RappBridgeAction(
        kind: .awaitUserApproval,
        operationId: operationId,
        operation: RappOperationDescriptor(operation))
    }
  }

  /// Applies the holder's approval of this exact request.
  public func approve(operationId: Data, approvedAtMs: UInt64) throws -> RappBridgeAction {
    try withProxy { engine, store in
      guard let request = engine.request(operationId) else { throw RappBindingError.WrongPhase }
      let approval = try UserApproval(for: request, approvedAtMilliseconds: approvedAtMs)
      return try engine.approve(
        operationIdentifier: operationId,
        approval: approval,
        store: &store,
        nowMilliseconds: approvedAtMs,
        maximumLifetimeMilliseconds: maximumLifetimeMilliseconds)
    }
  }

  /// Refuses the request because the holder denied it.
  public func deny(operationId: Data) throws -> RappBridgeAction {
    try finishFailure(operationId: operationId, failure: .userDenied)
  }

  /// Reports authenticated advisory progress on an active operation.
  public func reportProgress(operationId: Data, event: ProgressEvent) throws -> RappBridgeAction {
    try locked {
      guard case .proxy(let engine) = side else { throw RappBindingError.WrongPhase }
      let message = try mapping {
        try engine.reportProgress(operationIdentifier: operationId, event: event)
      }
      return RappBridgeAction(
        kind: .sendFrame,
        operationId: operationId,
        frame: try sealedMessage(message))
    }
  }

  /// Refuses a request this endpoint cannot present or serve.
  public func requestInvalidOrUnsupported(operationId: Data) throws -> RappBridgeAction {
    try finishFailure(operationId: operationId, failure: .requestInvalidOrUnsupported)
  }

  /// Refuses an automatic retry the policy forbids.
  public func retryRefused(operationId: Data) throws -> RappBridgeAction {
    try finishFailure(operationId: operationId, failure: .retryPolicyRefused)
  }

  /// Reports an incorrect credential with attempts remaining (section 10.2).
  ///
  /// The result carries the remaining count; the session and the pairing
  /// stay.
  public func invalidCredential(
    operationId: Data, remainingRetries: UInt8
  ) throws -> RappBridgeAction {
    guard remainingRetries > 0 else { throw RappBindingError.InvalidInput }
    return try finishFailure(
      operationId: operationId, failure: .invalidCredential(remainingRetries: remainingRetries))
  }

  /// Reports that the card blocked the credential (section 10.2); the
  /// pairing is revoked.
  public func credentialRejected(
    operationId: Data, rejectedAtMs _: UInt64
  ) throws -> RappBridgeAction {
    try finishFailure(operationId: operationId, failure: .credentialRejected)
  }

  /// Cancels after the card left before transmission provably began.
  public func cardRemovedBeforeTransmit(operationId: Data) throws -> RappBridgeAction {
    try finishFailure(operationId: operationId, failure: .cardRemovedBeforeTransmit)
  }

  /// Marks the operation ambiguous; the card command is never repeated.
  public func cardCompletionAmbiguous(operationId: Data) throws -> RappBridgeAction {
    try finishFailure(operationId: operationId, failure: .cardCompletionAmbiguous)
  }

  /// Answers an inspection.
  ///
  /// The answer to reset is the card's own, or its historical bytes; it is
  /// empty when the platform exposes neither.
  public func completeInspection(
    operationId: Data,
    answerToReset: Data,
    pin1Factory: Bool,
    pin2Factory: Bool,
    pin1Attempts: UInt8?,
    pin2Attempts: UInt8?,
    pukAttempts: UInt8?
  ) throws -> RappBridgeAction {
    var inspection = CardInspection(
      pin1Factory: pin1Factory,
      pin2Factory: pin2Factory,
      pin1Attempts: pin1Attempts,
      pin2Attempts: pin2Attempts,
      pukAttempts: pukAttempts)
    inspection.answerToReset = answerToReset
    return try complete(operationId: operationId, result: .inspection(inspection))
  }

  /// Answers an identity read (RAPP v26.10.1 §9.1).
  ///
  /// Both dates are `YYYY-MM-DD`; at least one DER certificate travels.
  public func completeIdentity(
    operationId: Data,
    holderName: String,
    cardId: String,
    issuanceDate: String,
    expirationDate: String,
    certificates: [Data]
  ) throws -> RappBridgeAction {
    let identity = CardIdentity(
      holderName: holderName, cardIdentifier: cardId, issuanceDate: issuanceDate,
      expirationDate: expirationDate, certificates: certificates, tokenDisplayName: nil)
    do {
      try identity.validate()
    } catch {
      throw RappBindingError.InvalidInput
    }
    return try complete(operationId: operationId, result: .identity(identity))
  }

  /// Answers a certificate read.
  public func completeCertificate(
    operationId: Data,
    der: Data,
    cardSerial: String? = nil
  ) throws -> RappBridgeAction {
    try complete(operationId: operationId, result: .certificate(der, cardSerial: cardSerial))
  }

  /// Answers a signature.
  public func completeSignature(operationId: Data, signature: Data) throws -> RappBridgeAction {
    try complete(operationId: operationId, result: .signature(signature))
  }

  /// Journals one batch signature before the next document is signed.
  ///
  /// A signature recorded here is delivered even if the batch is
  /// interrupted, and is never made again.
  public func recordBatchSignature(operationId: Data, signature: Data) throws {
    try locked {
      guard case .proxy(var engine) = side else { throw RappBindingError.WrongPhase }
      defer { side = .proxy(engine) }
      var store = VaultProxyJournalStore(vault: vault, pairIdentifier: pairIdentifier)
      try mapping {
        try engine.recordBatchSignature(
          operationIdentifier: operationId, signature: signature, store: &store)
      }
    }
  }

  /// Answers a batch once every document's signature is journaled.
  public func completeBatch(operationId: Data) throws -> RappBridgeAction {
    try withProxy { engine, store in
      try engine.completeBatch(operationIdentifier: operationId, store: &store)
    }
  }

  /// Releases a completed result once its acknowledgement reached transport.
  public func acknowledgmentReleased(operationId: Data) throws -> RappOperationResult {
    try locked {
      guard case .requester(var engine) = side else { throw RappBindingError.WrongPhase }
      defer { side = .requester(engine) }
      var store = VaultRequesterJournalStore(vault: vault, pairIdentifier: pairIdentifier)
      let result = try mapping {
        try engine.acknowledgementReleased(operationIdentifier: operationId, store: &store)
      }
      return RappOperationResult(result)
    }
  }
}

// swiftlint:enable function_parameter_count
