// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore

extension CardManagementModel {
  /// Mirrors the card-side floor in the form without replacing it.
  ///
  /// A missing report keeps the form responsive while the asynchronous probe
  /// arrives. Once a credential-specific reading exists, the UI cannot offer
  /// an operation the fresh same-session backend probe would refuse.
  ///
  /// Activation is judged on the credential it presents: under the
  /// activation-code scheme that is the PUK, whatever the factory-blocked
  /// PINs show; under the activation-PIN scheme it is every PIN still
  /// awaiting its factory-state write.
  internal var allowsActivationOperation: Bool {
    switch activationScheme {
    case .activationCodeIsPuk:
      return allowsCredentialOperation(spending: .puk)

    case .presetActivationPin, .none:
      return (!activationNeeds.pin1 || allowsCredentialOperation(spending: .pin1))
        && (!activationNeeds.pin2 || allowsCredentialOperation(spending: .pin2))
    }
  }

  private func retryOutcome(for role: CredentialRole) -> RetryProbeOutcome? {
    switch role {
    case .pin1:
      report?.pin1

    case .pin2:
      report?.pin2

    case .puk:
      report?.puk
    }
  }

  internal func allowsCredentialOperation(spending role: CredentialRole) -> Bool {
    guard let outcome = retryOutcome(for: role) else { return true }
    return RetryFloor.evaluate(probeOutcome: outcome) == .proceed
  }
}
