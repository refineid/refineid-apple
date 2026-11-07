// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension VirtualIDCard {
  /// A counter the card reports as blocked.
  internal static let noAttemptsLeft: UInt8 = 0

  internal func change(
    role: CredentialRole,
    operation: Operation,
    current entered: String,
    new: String
  ) -> MutationResult {
    guard credentialIsValid(entered, for: role),
      credentialIsValid(new, for: role),
      entered != new
    else {
      return MutationResult(outcome: .invalidEntry, snapshot: current)
    }
    if let failure = operationFailure() {
      return MutationResult(
        outcome: .transportFailure(failure),
        snapshot: current)
    }
    if let fault = consumeFault(for: operation, phase: .beforeCommand) {
      return MutationResult(
        outcome: .transportFailure(fault),
        snapshot: current)
    }
    var credential = credential(for: role)
    if let refusal = retryRefusal(credential.attemptsRemaining, presenting: role) {
      return MutationResult(outcome: refusal, snapshot: current)
    }
    let outcome: CredentialOutcome
    if entered != credential.value {
      credential.attemptsRemaining -= 1
      setCredential(credential, for: role)
      outcome =
        credential.attemptsRemaining == 0
        ? .blocked
        : .rejected(remaining: credential.attemptsRemaining)
    } else {
      credential.value = new
      credential.attemptsRemaining = RetryCount.pristineAllowance
      credential.isFactoryValue = false
      setCredential(credential, for: role)
      outcome = .success
    }
    if let fault = consumeFault(for: operation, phase: .afterCardExecution) {
      return MutationResult(
        outcome: .transportFailure(fault),
        snapshot: current)
    }
    return MutationResult(outcome: outcome, snapshot: current)
  }

  internal func reset(
    role: CredentialRole,
    operation: Operation,
    puk enteredPUK: String,
    new: String
  ) -> MutationResult {
    guard
      digitsAreValid(
        enteredPUK,
        within: Puk.minimumDigitCount...Puk.maximumDigitCount),
      credentialIsValid(new, for: role)
    else {
      return MutationResult(outcome: .invalidEntry, snapshot: current)
    }
    if let failure = operationFailure() {
      return MutationResult(
        outcome: .transportFailure(failure),
        snapshot: current)
    }
    if let fault = consumeFault(for: operation, phase: .beforeCommand) {
      return MutationResult(
        outcome: .transportFailure(fault),
        snapshot: current)
    }
    if let refusal = retryRefusal(current.card.puk.attemptsRemaining, presenting: .puk) {
      return MutationResult(outcome: refusal, snapshot: current)
    }
    let outcome: CredentialOutcome
    if current.card.puk.attemptsRemaining == Self.noAttemptsLeft {
      outcome = .blocked
    } else if enteredPUK != current.card.puk.value {
      current.card.puk.attemptsRemaining -= 1
      outcome =
        current.card.puk.attemptsRemaining == 0
        ? .blocked
        : .rejected(remaining: current.card.puk.attemptsRemaining)
    } else {
      var target = credential(for: role)
      target.value = new
      target.attemptsRemaining = RetryCount.pristineAllowance
      target.isFactoryValue = false
      setCredential(target, for: role)
      current.card.puk.attemptsRemaining = RetryCount.pristineAllowance
      outcome = .success
    }
    if let fault = consumeFault(for: operation, phase: .afterCardExecution) {
      return MutationResult(
        outcome: .transportFailure(fault),
        snapshot: current)
    }
    return MutationResult(outcome: outcome, snapshot: current)
  }

  internal func activateCredential(
    role: CredentialRole,
    operation: Operation,
    entry: String,
    new: String
  ) -> CredentialOutcome {
    if let failure = operationFailure() {
      return .transportFailure(failure)
    }
    if let fault = consumeFault(for: operation, phase: .beforeCommand) {
      return .transportFailure(fault)
    }
    let checkedRole: CredentialRole =
      current.card.activationScheme == .activationCodeIsPuk ? .puk : role
    var checked = credential(for: checkedRole)
    if let refusal = lastTriesRefusal(checked.attemptsRemaining) {
      return refusal
    }
    if checked.attemptsRemaining == Self.noAttemptsLeft {
      return .blocked
    }
    if entry != current.card.activationEntry {
      checked.attemptsRemaining -= 1
      setCredential(checked, for: checkedRole)
      return checked.attemptsRemaining == 0
        ? .blocked
        : .rejected(remaining: checked.attemptsRemaining)
    }
    var target = credential(for: role)
    target.value = new
    target.attemptsRemaining = RetryCount.pristineAllowance
    target.isFactoryValue = false
    setCredential(target, for: role)
    if checkedRole == .puk {
      current.card.puk.attemptsRemaining = RetryCount.pristineAllowance
    }
    if let fault = consumeFault(for: operation, phase: .afterCardExecution) {
      return .transportFailure(fault)
    }
    return .success
  }

  /// What the software refuses before presenting `role`.
  ///
  /// One or two tries left refuse for every credential, and none left
  /// for a PIN. The PUK at no tries left goes to the card, which answers
  /// blocked itself and spends nothing.
  internal func retryRefusal(
    _ remaining: UInt8,
    presenting role: CredentialRole
  ) -> CredentialOutcome? {
    switch role {
    case .pin1, .pin2:
      remaining == Self.noAttemptsLeft ? .blocked : lastTriesRefusal(remaining)

    case .puk:
      lastTriesRefusal(remaining)
    }
  }

  /// What the software refuses before an activation presents a
  /// credential, or before any use of the PUK.
  ///
  /// Only one or two tries left refuse. None left goes to the card,
  /// which answers blocked itself.
  internal func lastTriesRefusal(_ remaining: UInt8) -> CredentialOutcome? {
    switch remaining {
    case 1...RetryCount.lowAttemptCeiling:
      .refusedLowAttempts(remaining: remaining)

    default:
      nil
    }
  }

  internal func credentialIsValid(
    _ digits: String,
    for role: CredentialRole
  ) -> Bool {
    switch role {
    case .pin1:
      digitsAreValid(
        digits,
        within: Pin1.minimumDigitCount...Pin1.maximumDigitCount)

    case .pin2:
      digitsAreValid(
        digits,
        within: Pin2.minimumDigitCount...Pin2.maximumDigitCount)

    case .puk:
      digitsAreValid(
        digits,
        within: Puk.minimumDigitCount...Puk.maximumDigitCount)
    }
  }

  internal func digitsAreValid(
    _ digits: String,
    within allowedCount: ClosedRange<Int>
  ) -> Bool {
    let asciiDigits = UInt8(ascii: "0")...UInt8(ascii: "9")
    return allowedCount.contains(digits.count)
      && digits.utf8.allSatisfy { asciiDigits.contains($0) }
  }

  private func credential(for role: CredentialRole) -> CredentialState {
    switch role {
    case .pin1:
      current.card.pin1

    case .pin2:
      current.card.pin2

    case .puk:
      current.card.puk
    }
  }

  private func setCredential(
    _ credential: CredentialState,
    for role: CredentialRole
  ) {
    switch role {
    case .pin1:
      current.card.pin1 = credential

    case .pin2:
      current.card.pin2 = credential

    case .puk:
      current.card.puk = credential
    }
  }

  internal func consumeFault(
    for operation: Operation,
    phase: FaultPhase
  ) -> FaultEffect? {
    guard
      let index = current.faults.firstIndex(where: { fault in
        (fault.operation == operation || fault.operation == .any)
          && fault.phase == phase
      })
    else {
      return nil
    }
    let effect = current.faults[index].effect
    if current.faults[index].remainingOccurrences > 1 {
      current.faults[index].remainingOccurrences -= 1
    } else {
      current.faults.remove(at: index)
    }
    switch effect {
    case .readerDisconnected:
      current.card.readerConnected = false
      current.card.cardPresent = false

    case .cardRemoved:
      current.card.cardPresent = false

    case .connectionLost, .timeout, .malformedResponse, .tokenNotPublished:
      break
    }
    return effect
  }
}
