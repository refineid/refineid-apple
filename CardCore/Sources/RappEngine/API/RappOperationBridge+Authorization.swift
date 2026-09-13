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
    try withProxy { engine, _ in
      guard let request = engine.request(operationId) else { throw RappBindingError.WrongPhase }
      let approval = try UserApproval(for: request, approvedAtMilliseconds: approvedAtMs)
      return try engine.approve(
        operationIdentifier: operationId,
        approval: approval,
        nowMilliseconds: approvedAtMs,
        maximumLifetimeMilliseconds: maximumLifetimeMilliseconds)
    }
  }

  /// Refuses the request because the holder denied it.
  public func deny(operationId: Data) throws -> RappBridgeAction {
    try finishFailure(operationId: operationId, error: .userDenied)
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
    try finishFailure(operationId: operationId, error: .requestInvalidOrUnsupported)
  }

  /// Refuses an automatic retry the policy forbids.
  public func retryRefused(operationId: Data) throws -> RappBridgeAction {
    try finishFailure(operationId: operationId, error: .retryPolicyRefused)
  }

  /// Reports that the card rejected the credential.
  public func credentialRejected(
    operationId: Data, rejectedAtMs _: UInt64
  ) throws -> RappBridgeAction {
    try finishFailure(operationId: operationId, error: .credentialRejected)
  }

  /// Cancels after the card left before transmission provably began.
  public func cardRemovedBeforeTransmit(operationId: Data) throws -> RappBridgeAction {
    try finishFailure(operationId: operationId, error: .cardRemovedBeforeTransmit)
  }

  /// Marks the operation ambiguous; the card command is never repeated.
  public func cardCompletionAmbiguous(operationId: Data) throws -> RappBridgeAction {
    try finishFailure(operationId: operationId, error: .cardCompletionAmbiguous)
  }

  /// Answers an inspection.
  public func completeInspection(
    operationId: Data,
    pin1Factory: Bool,
    pin2Factory: Bool,
    pin1Attempts: UInt8?,
    pin2Attempts: UInt8?,
    pukAttempts: UInt8?
  ) throws -> RappBridgeAction {
    try complete(
      operationId: operationId,
      result: .inspection(
        CardInspection(
          pin1Factory: pin1Factory,
          pin2Factory: pin2Factory,
          pin1Attempts: pin1Attempts,
          pin2Attempts: pin2Attempts,
          pukAttempts: pukAttempts)))
  }

  /// Answers an identity read.
  public func completeIdentity(
    operationId: Data, displayName: String, personId: String
  ) throws -> RappBridgeAction {
    try complete(
      operationId: operationId,
      result: .identity(displayName: displayName, personIdentifier: personId))
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
