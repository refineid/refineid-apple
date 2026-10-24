// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

extension CardManagementModel {
  internal func describe(_ activation: CardMaintenance.ActivationReport) -> Bool {
    let entry = activationEntryName(activation.scheme)
    switch (activation.pin1, activation.pin2) {
    case (.success, .success):
      notice = "Card activated: PIN 1 and PIN 2 are set"
      return true

    case (.alreadyActivated, .success):
      notice = "Card activated: PIN 2 is set; PIN 1 already was"
      return true

    case (.success, .alreadyActivated), (.success, nil):
      notice = "Card activated: PIN 1 is set; PIN 2 already was"
      return true

    case (.success, .some(let second)):
      failure = message(
        for: second, presenting: entry,
        spending: activationSpends(activation.scheme, writing: .pin2)
      )
      .map { "PIN 1 was set, but PIN 2 was not: \($0)" }
      return false

    case (.alreadyActivated, .some(let second)):
      failure = message(
        for: second, presenting: entry,
        spending: activationSpends(activation.scheme, writing: .pin2)
      )
      .map { "PIN 2 was not set: \($0)" }
      return false

    case (.alreadyActivated, nil):
      failure = "This card is already activated."
      return false

    case (let first, _):
      failure = message(
        for: first, presenting: entry,
        spending: activationSpends(activation.scheme, writing: .pin1))
      return false
    }
  }

  /// The credential an activation write presents: the activation code
  /// is the PUK; an activation PIN is the PIN it replaces.
  private func activationSpends(
    _ scheme: ActivationScheme,
    writing role: CredentialRole
  ) -> CredentialRole {
    switch scheme {
    case .activationCodeIsPuk:
      .puk

    case .presetActivationPin:
      role
    }
  }

  internal func activationEntryName(_ scheme: ActivationScheme) -> String {
    switch scheme {
    case .activationCodeIsPuk:
      "activation code"

    case .presetActivationPin:
      "activation PIN"
    }
  }

  internal func perform(
    presenting: String,
    spending role: CredentialRole,
    accepted: String,
    _ operation: () async -> CardMaintenance.MutationReport
  ) async -> Bool {
    guard beginCardOperation() else { return false }
    working = true
    failure = nil
    notice = nil
    let mutation = await operation()
    working = false
    if mutation.outcome == .success {
      notice = accepted
    } else {
      failure = message(for: mutation.outcome, presenting: presenting, spending: role)
    }
    if let snapshot = mutation.snapshot {
      apply(snapshot, preservingOutcome: true)
    }
    return mutation.outcome == .success
  }

  /// Starts a mutating card operation or explains why it could not start.
  ///
  /// Buttons mirror these conditions, but confirmation is asynchronous: card
  /// removal or an event-driven refresh can happen while the system alert is
  /// visible. A confirmed operation must never disappear as a silent no-op.
  internal func beginCardOperation() -> Bool {
    if cardOperationInProgress {
      failure = "Another card operation is still in progress. Try again."
      return false
    }
    guard canContactCard else {
      failure = unreadableCardMessage
      return false
    }
    return true
  }

  internal func message(
    for outcome: CardMaintenance.Outcome,
    presenting: String,
    spending role: CredentialRole
  ) -> String? {
    switch outcome {
    case .success:
      nil

    case .invalidEntry:
      "The entry does not fit the credential's digit rules."

    case .noCard:
      unreadableCardMessage

    case .pinBlocked:
      CredentialOutcomeMessage.blocked(role)

    case .floorRefused(.refuseUnreadable):
      "The \(presenting) retry counter could not be read; nothing was sent."

    case .floorRefused(let verdict):
      CredentialOutcomeMessage.floorRefusal(role: role, verdict: verdict, remaining: nil)

    case .rejected(let remaining):
      CredentialOutcomeMessage.rejection(
        credentialName: presenting,
        remaining: remaining)

    case .invalidated:
      "The credential slot is invalidated; only the issuer can recover it."

    case .alreadyActivated:
      "This card looks activated already."

    case .failed:
      "The card operation did not complete."
    }
  }
}
