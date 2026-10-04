// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// What the credential screen knows and what it is allowed to do.
///
/// Nothing here ever holds a secret longer than the moment it is written:
/// the entry fields are cleared as soon as a value is stored. For PIN1
/// the model only ever reports *whether* something is stored, never what
/// it is -- a screen that can show a PIN is a screen that can leak one.
/// The card access number is the one value read back: it is printed on
/// the card face and is the holder's to see.
@MainActor
internal final class CardCredentialsModel: ObservableObject {
  // MARK: Nested Types

  internal enum ConnectionResult: Sendable {
    case activated
    case activationRequired(
      scheme: ActivationScheme,
      needs: CardActivationNeeds)
    case wrongCardAccessNumber
    case failed
  }

  // MARK: Properties

  /// What the device currently holds.
  @Published internal private(set) var contents = CardCredentialStore.contents()

  /// The stored card access number, shown by the manager window.
  @Published internal private(set) var storedCardAccessNumber =
    CardCredentialStore.displayedCardAccessNumber()

  /// Whether there is anything behind the destructive forget action.
  @Published internal private(set) var hasForgettableState =
    CardStateReset.hasForgettableState()

  /// Set when the last action failed, for the holder to read.
  @Published internal private(set) var failure: String?

  /// True only while the initial, side-effect-free card classification runs.
  @Published internal private(set) var isConnecting = false

  /// True only after this launch has classified the live card and, for an
  /// activated card, obtained a complete credential retry report.
  @Published internal private(set) var hasVerifiedCardStatus = false

  // MARK: Functions

  /// Establishes PACE with an entered CAN and classifies the live card.
  ///
  /// Nothing is persisted and no credential-changing command is sent.
  internal func connect(cardAccessNumber: String) async -> ConnectionResult? {
    guard !isConnecting,
      CardAccessNumber(digits: cardAccessNumber) != nil
    else { return nil }
    isConnecting = true
    failure = nil
    hasVerifiedCardStatus = false
    CredentialRetryHealth.shared.clear()
    defer { isConnecting = false }
    let result = await CardMaintenance.connectionSnapshot(
      cardAccessNumber: cardAccessNumber)
    let snapshot: CardMaintenance.Snapshot
    switch result {
    case .connected(let connected):
      snapshot = connected

    case .wrongCardAccessNumber:
      CardCredentialStore.forgetCardAccessNumber()
      refresh()
      failure = String(localized: "The Card Access Number (CAN) is incorrect.")
      return .wrongCardAccessNumber

    case .failed:
      failure = String(localized: "The identity card could not be read. Try again.")
      return .failed
    }
    if let scheme = snapshot.activationScheme,
      let needs = snapshot.activationNeeds,
      needs.any
    {
      CredentialRetryHealth.shared.update(snapshot.report)
      hasVerifiedCardStatus = true
      return .activationRequired(scheme: scheme, needs: needs)
    }
    if snapshot.activationScheme != nil, snapshot.activationNeeds != nil {
      CredentialRetryHealth.shared.update(snapshot.report)
      guard CredentialRetryHealth.shared.level != nil else {
        failure = String(localized: "The identity card could not be read. Try again.")
        return .failed
      }
      hasVerifiedCardStatus = true
      return .activated
    }
    failure = String(localized: "The identity card could not be classified. Try again.")
    return .failed
  }

  /// Removes a correction message as soon as the holder starts again.
  internal func clearFailure() {
    failure = nil
  }

  /// Invalidates a live classification when the CAN it belongs to changes.
  internal func invalidateCardStatus() {
    hasVerifiedCardStatus = false
    CredentialRetryHealth.shared.clear()
  }

  /// Refreshes what is stored, without touching PIN1.
  internal func refresh() {
    let refreshedContents = CardCredentialStore.contents()
    let refreshedCardAccessNumber = CardCredentialStore.displayedCardAccessNumber()
    let refreshedForgettableState = CardStateReset.hasForgettableState()

    // Publish the value before the presence flag. Views reacting to a
    // removed credential must see nil, not briefly restore the old CAN
    // and feed it back through automatic persistence.
    storedCardAccessNumber = refreshedCardAccessNumber
    contents = refreshedContents
    hasForgettableState = refreshedForgettableState
  }

  /// Stores the card access number, with no gate in front.
  ///
  /// Ungated: the number is printed on the card face, so a prompt in
  /// front of storing it protected nothing and cost every setup an
  /// interruption.
  @discardableResult
  internal func saveCardAccessNumber(_ digits: String) -> Bool {
    failure = nil
    guard CardCredentialStore.save(cardAccessNumber: digits) == errSecSuccess else {
      CardCredentialStore.forgetCardAccessNumber()
      refresh()
      return false
    }
    refresh()
    return contents.hasCardAccessNumber
  }

  /// Stores PIN1, with no gate in front.
  ///
  /// Ungated like the card access number. A prompt here protected only
  /// the act of writing a PIN the holder just typed: the extension reads
  /// the stored value without any gate -- it must, inside a two-second
  /// signing field -- so possession of the unlocked phone plus the card
  /// already signs, gate or no gate. The card's own retry counter is the
  /// control that actually stops a guessed PIN.
  @discardableResult
  internal func savePin1(_ digits: String) -> Bool {
    failure = nil
    guard CardCredentialStore.save(pin1: digits) == errSecSuccess else {
      CardCredentialStore.forgetPin1()
      refresh()
      return false
    }
    refresh()
    return contents.hasPin1
  }

  /// Forgets the card access number, so it can be entered again.
  ///
  /// Ungated, like storing it.
  internal func forgetCardAccessNumber() {
    failure = nil
    invalidateCardStatus()
    CardCredentialStore.forgetCardAccessNumber()
    refresh()
  }

  /// Forgets PIN1, so every signature asks again.
  ///
  /// Deletion is deliberately ungated: it removes signing authority from
  /// this device and never reveals the stored value.
  internal func forgetPin1() {
    failure = nil
    CardCredentialStore.forgetPin1()
    refresh()
  }

  /// Forgets everything this device knows about the card.
  ///
  /// This clears credentials, card-directory entries, primed identities,
  /// Safari registration, diagnostic logs, and the whole RAPP
  /// configuration without authentication. Nothing is disclosed;
  /// authority is removed, and remote devices start over with the
  /// pairing ceremony.
  internal func forgetEverything() async {
    failure = nil
    invalidateCardStatus()
    let outcome = await CardIdentityRemoval.perform()
    refresh()
    if !outcome.succeeded {
      failure = outcome.summary
    }
  }

  /// Forgets everything after the card refused the stored CAN.
  ///
  /// The refusal message set by the failed connection stays visible:
  /// it is the only account of why the identity is gone.
  internal func forgetEverythingAfterCardMismatch() async {
    let explanation = failure
    await forgetEverything()
    if failure == nil {
      failure = explanation
    }
  }
}
