// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore

extension CardMaintenance {
  internal typealias ActivationNeeds = CardActivationNeeds

  internal struct ActivationReport: Equatable, Sendable {
    internal let scheme: ActivationScheme
    internal let pin1: Outcome
    internal let pin2: Outcome?
  }

  /// What the activation form needs from a card in a reader before it
  /// is drawn.
  internal struct ReaderActivation: Equatable, Sendable {
    internal let activation: ActivationClassification
    internal let pinLengths: CardPinLengths
  }

  internal struct ActivationExecution: Equatable, Sendable {
    internal let activation: ActivationReport
    internal let remaining: ActivationNeeds
  }

  internal struct ActivationRequest: Sendable {
    internal let entry: String
    internal let newPin1: String?
    internal let newPin2: String?
    internal let scheme: ActivationScheme
    internal let needs: ActivationNeeds
  }

  internal static func activate(
    request: ActivationRequest,
    transport: Transport,
    cardAccessNumber: String?
  ) async -> ActivationExecution? {
    if await DemoMode.shared.isActive {
      return await DemoMode.shared.activateCard(request: request)
    }
    return await onCard(
      transport: transport,
      cardAccessNumber: cardAccessNumber,
      operation: .activation,
      failedStep: Self.failedStep(of:)
    ) { operations -> ActivationExecution? in
      guard
        let lengths = try? operations.readCardPinLengths(),
        let activation = runActivation(operations, request: request, lengths: lengths)
      else {
        return nil
      }
      // Mutation is complete before any state inspection begins. A successful
      // command response is authoritative even if the postflight cannot read
      // the changed-since-manufacture record after secure messaging ends.
      let observed = operations.activationNeeds(scheme: request.scheme)
      let remaining = ActivationNeeds(
        pin1: request.needs.pin1
          && activation.pin1 != .success
          && observed.pin1,
        pin2: request.needs.pin2
          && activation.pin2 != .some(.success)
          && observed.pin2
      )
      return ActivationExecution(
        activation: activation,
        remaining: remaining
      )
    }
    .flatMap(\.self)
  }

  /// Where on the meter an activation broke: at the credential while any
  /// PIN still needs activating.
  private static func failedStep(of execution: ActivationExecution?) -> NearFieldStep? {
    execution?.remaining.any == false ? nil : .credential
  }

  private static func runActivation(
    _ operations: CardOperations,
    request: ActivationRequest,
    lengths: CardPinLengths
  ) -> ActivationReport? {
    let scheme = request.scheme
    let needs = request.needs
    guard request.entry.count == scheme.activationEntryDigitCount else {
      return ActivationReport(
        scheme: scheme,
        pin1: .invalidEntry,
        pin2: nil)
    }
    guard needs.any else {
      return ActivationReport(scheme: scheme, pin1: .alreadyActivated, pin2: nil)
    }
    if needs.pin1, request.newPin1.flatMap({ Pin1(digits: $0) }) == nil {
      return ActivationReport(scheme: scheme, pin1: .invalidEntry, pin2: nil)
    }
    if needs.pin2, request.newPin2.flatMap({ Pin2(digits: $0) }) == nil {
      return ActivationReport(scheme: scheme, pin1: .invalidEntry, pin2: nil)
    }

    var first: Outcome = .alreadyActivated
    if needs.pin1, let fresh = request.newPin1 {
      first = activationStep(
        operations,
        scheme: scheme,
        entry: request.entry,
        newPin1: fresh,
        lengths: lengths
      )
      guard first == .success else {
        return ActivationReport(scheme: scheme, pin1: first, pin2: nil)
      }
    }

    var second: Outcome? = .alreadyActivated
    if needs.pin2, let fresh = request.newPin2 {
      second = activationStep(
        operations,
        scheme: scheme,
        entry: request.entry,
        newPin2: fresh,
        lengths: lengths
      )
    }
    return ActivationReport(scheme: scheme, pin1: first, pin2: second)
  }

  private static func activationStep(
    _ operations: CardOperations,
    scheme: ActivationScheme,
    entry: String,
    newPin1: String,
    lengths: CardPinLengths
  ) -> Outcome {
    switch scheme {
    case .activationCodeIsPuk:
      guard let code = Puk(digits: entry), let pin = Pin1(digits: newPin1) else {
        return .invalidEntry
      }
      if let refusal = activationFloorRefusal(operations, role: .puk) {
        return refusal
      }
      do {
        try operations.unblockPin1(
          puk: code.consumeForSingleTransmission(),
          new: pin.consumeForSingleTransmission(),
          lengths: lengths
        )
        return .success
      } catch {
        return outcome(of: error)
      }

    case .presetActivationPin:
      guard let preset = Pin1(digits: entry), let pin = Pin1(digits: newPin1) else {
        return .invalidEntry
      }
      if let refusal = activationFloorRefusal(operations, role: .pin1) {
        return refusal
      }
      do {
        try operations.changePin1(
          current: preset.consumeForSingleTransmission(),
          new: pin.consumeForSingleTransmission(),
          lengths: lengths
        )
        return .success
      } catch {
        return outcome(of: error)
      }
    }
  }

  private static func activationStep(
    _ operations: CardOperations,
    scheme: ActivationScheme,
    entry: String,
    newPin2: String,
    lengths: CardPinLengths
  ) -> Outcome {
    switch scheme {
    case .activationCodeIsPuk:
      guard let code = Puk(digits: entry), let pin = Pin2(digits: newPin2) else {
        return .invalidEntry
      }
      if let refusal = activationFloorRefusal(operations, role: .puk) {
        return refusal
      }
      do {
        try operations.unblockPin2(
          puk: code.consumeForSingleTransmission(),
          new: pin.consumeForSingleTransmission(),
          lengths: lengths
        )
        return .success
      } catch {
        return outcome(of: error)
      }

    case .presetActivationPin:
      guard let preset = Pin2(digits: entry), let pin = Pin2(digits: newPin2) else {
        return .invalidEntry
      }
      if let refusal = activationFloorRefusal(operations, role: .pin2) {
        return refusal
      }
      do {
        try operations.changePin2(
          current: preset.consumeForSingleTransmission(),
          new: pin.consumeForSingleTransmission(),
          lengths: lengths
        )
        return .success
      } catch {
        return outcome(of: error)
      }
    }
  }

  /// Applies the shared `{1, 2}` refusal set immediately before one
  /// activation write.
  ///
  /// This probe is credential state, not a certificate read, and each
  /// PIN receives its own fresh decision.
  private static func activationFloorRefusal(
    _ operations: CardOperations,
    role: CredentialRole
  ) -> Outcome? {
    guard let probe = try? operations.probeRetryCounter(role: role) else {
      return .floorRefused(.refuseUnreadable)
    }
    let verdict = RetryFloor.evaluate(probeOutcome: probe)
    return verdict == .proceed ? nil : .floorRefused(verdict)
  }
}
