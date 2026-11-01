// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension VirtualIDCard {
  /// Activates factory PINs using the card's activation entry.
  ///
  /// PIN 1 is activated first and PIN 2 only after PIN 1 succeeds; on
  /// the activation-code scheme the PUK's retry counter guards the entry.
  public func activate(_ request: ActivationRequest) -> ActivationResult {
    let needsPIN1 = current.card.pin1.isFactoryValue
    let needsPIN2 = current.card.pin2.isFactoryValue
    if let rejection = activationRejection(
      for: request, needsPIN1: needsPIN1, needsPIN2: needsPIN2)
    {
      return rejection
    }

    var pin1Outcome: CredentialOutcome = .alreadyActivated
    if needsPIN1, let newPIN1 = request.newPIN1 {
      pin1Outcome = activateCredential(
        role: .pin1,
        operation: .activatePIN1,
        entry: request.entry,
        new: newPIN1)
      guard pin1Outcome == .success else {
        return ActivationResult(
          pin1: pin1Outcome,
          pin2: nil,
          snapshot: current)
      }
    }

    var pin2Outcome: CredentialOutcome? = .alreadyActivated
    if needsPIN2, let newPIN2 = request.newPIN2 {
      pin2Outcome = activateCredential(
        role: .pin2,
        operation: .activatePIN2,
        entry: request.entry,
        new: newPIN2)
    }
    let pin1Completed =
      pin1Outcome == .success
      || pin1Outcome == .alreadyActivated
    let pin2Completed =
      pin2Outcome.map { outcome in
        outcome == .success || outcome == .alreadyActivated
      } ?? true
    if current.card.transport == .nearField,
      !activationRequired,
      pin1Completed,
      pin2Completed
    {
      current.device.storedCardAccessNumber =
        current.device.connectedCardAccessNumber
        ?? current.card.cardAccessNumber
    }
    return ActivationResult(
      pin1: pin1Outcome,
      pin2: pin2Outcome,
      snapshot: current)
  }

  /// The result an activation request earns before any credential changes,
  /// or nil when the request is well formed enough to attempt.
  private func activationRejection(
    for request: ActivationRequest,
    needsPIN1: Bool,
    needsPIN2: Bool
  ) -> ActivationResult? {
    guard needsPIN1 || needsPIN2 else {
      return ActivationResult(
        pin1: .alreadyActivated,
        pin2: nil,
        snapshot: current)
    }
    guard
      digitsAreValid(
        request.entry,
        within: activationEntryDigitCount...activationEntryDigitCount)
    else {
      return ActivationResult(
        pin1: .invalidEntry,
        pin2: nil,
        snapshot: current)
    }
    if needsPIN1,
      request.newPIN1.map({ credentialIsValid($0, for: .pin1) }) != true
    {
      return ActivationResult(
        pin1: .invalidEntry,
        pin2: nil,
        snapshot: current)
    }
    if needsPIN2,
      request.newPIN2.map({ credentialIsValid($0, for: .pin2) }) != true
    {
      return ActivationResult(
        pin1: needsPIN1 ? .invalidEntry : .alreadyActivated,
        pin2: .invalidEntry,
        snapshot: current)
    }
    return nil
  }

  /// Registers the card's token on the device over the connection whose
  /// access number the card proved; no PIN is asked for or stored (RAPP
  /// v26.10.29 §11 item 2).
  public func register() -> RegistrationResult {
    if let failure = operationFailure() {
      return .transportFailure(failure)
    }
    if let fault = consumeFault(for: .register, phase: .beforeCommand) {
      return .transportFailure(fault)
    }
    guard current.card.authenticationCertificate == .valid else {
      return .certificateUnavailable
    }
    if let fault = consumeFault(for: .register, phase: .afterCardExecution) {
      if fault == .tokenNotPublished {
        current.device.cachedIdentity = true
        current.device.tokenRegistered = false
        return .tokenPublicationFailed(current)
      }
      return .transportFailure(fault)
    }
    current.device.storedCardAccessNumber =
      current.device.connectedCardAccessNumber
      ?? current.device.storedCardAccessNumber
      ?? current.card.cardAccessNumber
    current.device.cachedIdentity = true
    current.device.tokenRegistered = true
    return .success(current)
  }

  /// Authorizes one virtual qualified signature with the same retry floor
  /// and state transitions as the physical card boundary.
  public func authorizeQualifiedSignature(pin2: String) -> SignatureResult {
    current.device.pendingSigningRequest = true
    guard credentialIsValid(pin2, for: .pin2) else {
      return finishSignature(.invalidEntry)
    }
    if let failure = operationFailure() {
      return finishSignature(.transportFailure(failure))
    }
    if let fault = consumeFault(
      for: .qualifiedSignature,
      phase: .beforeCommand)
    {
      return finishSignature(.transportFailure(fault))
    }
    guard current.card.signatureCertificate == .valid else {
      return finishSignature(.certificateUnavailable)
    }
    switch current.card.pin2.attemptsRemaining {
    case 0:
      return finishSignature(.blocked)

    case 1...RetryCount.lowAttemptCeiling:
      return finishSignature(
        .refusedLowAttempts(remaining: current.card.pin2.attemptsRemaining))

    default:
      break
    }
    if pin2 != current.card.pin2.value {
      current.card.pin2.attemptsRemaining -= 1
      let remaining = current.card.pin2.attemptsRemaining
      return finishSignature(
        remaining == 0 ? .blocked : .rejected(remaining: remaining))
    }
    current.card.pin2.attemptsRemaining = RetryCount.pristineAllowance
    if let fault = consumeFault(
      for: .qualifiedSignature,
      phase: .afterCardExecution)
    {
      return finishSignature(.transportFailure(fault))
    }
    return finishSignature(.success)
  }

  private func finishSignature(_ result: SignatureResult) -> SignatureResult {
    current.device.pendingSigningRequest = false
    return result
  }

  internal func reachabilityFailure() -> FaultEffect? {
    guard current.card.cardPresent else { return .cardRemoved }
    if current.card.transport == .reader, !current.card.readerConnected {
      return .readerDisconnected
    }
    return nil
  }

  internal func operationFailure() -> FaultEffect? {
    if let failure = reachabilityFailure() {
      return failure
    }
    if current.card.transport == .nearField {
      let offered =
        current.device.connectedCardAccessNumber
        ?? current.device.storedCardAccessNumber
      guard offered == current.card.cardAccessNumber else {
        return .connectionLost
      }
    }
    return nil
  }

}
