// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore

extension CardManagementModel {
  /// Why the activation form cannot go to the card; nil when it can.
  ///
  /// Mirrors the card-side floor in the form without replacing it: a
  /// missing report keeps the form responsive while the asynchronous probe
  /// arrives, and once a reading exists the UI cannot offer an operation
  /// the fresh same-session backend probe would refuse.
  ///
  /// Activation is judged on the credential it presents: under the
  /// activation-code scheme that is the PUK, whatever the factory-blocked
  /// PINs show; under the activation-PIN scheme it is every PIN still
  /// awaiting its factory-state write. A reading of no tries left or
  /// blocked is no reason: the backend lets the command reach the card,
  /// and the card answers for itself.
  internal var activationBlockedReason: String? {
    switch activation?.scheme {
    case .activationCodeIsPuk:
      return blockedReason(presenting: .activationCode, spending: .puk)

    case .presetActivationPin, .none:
      let pin1 =
        activationNeeds.pin1
        ? blockedReason(presenting: .activationPin, spending: .pin1) : nil
      let pin2 =
        activationNeeds.pin2
        ? blockedReason(presenting: .activationPin, spending: .pin2) : nil
      return pin1 ?? pin2
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
    return RetryFloor.evaluate(probeOutcome: outcome, presenting: role) == .proceed
  }

  /// Why a form with valid entries cannot go to the card, in the words the
  /// operation's own refusal uses; nil when it can.
  ///
  /// `presenting` names the entry in the unreadable case, and `role` is
  /// the credential whose counter is judged.
  internal func blockedReason(
    presenting: PresentedCredential,
    spending role: CredentialRole
  ) -> String? {
    if cardOperationInProgress {
      return String(localized: "Another card operation is still in progress. Try again.")
    }
    guard canContactCard else { return unreadableCardMessage }
    guard let outcome = retryOutcome(for: role) else { return nil }
    switch RetryFloor.evaluate(probeOutcome: outcome, presenting: role) {
    case .proceed:
      return nil

    case .refuseUnreadable:
      return presenting.unreadableCounterMessage

    case .refuseLowAttempts:
      var remaining: RetryCount?
      if case .remaining(let count) = outcome { remaining = count }
      return CredentialOutcomeMessage.floorRefusal(
        role: role, verdict: .refuseLowAttempts, remaining: remaining)
    }
  }
}
