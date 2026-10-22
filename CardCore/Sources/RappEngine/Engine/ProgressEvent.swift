// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are ordered as an operation reaches them, as the specification
// lists them, so the source reads line for line against the document.
// swiftlint:disable sorted_enum_cases

import Foundation

/// A change of a pending operation's state the custodian reports (RAPP
/// v26.10.22 §7.1, §8.2).
public enum ProgressEvent: String, Sendable, Equatable, CaseIterable {
  /// Another session's operation holds the card (§8.2 item 2).
  case queued = "queued"
  /// The custodian's PIN prompt is on screen; entering the PIN is the
  /// holder's consent (§8.2 item 3). Never sent when no prompt is shown.
  case consentShown = "consent_shown"
  /// The custodian waits for the holder to present the card (§8.2 item 4).
  case waitingForCard = "waiting_for_card"
  /// The card was found or the wait is over.
  case cardWaitEnded = "card_wait_ended"
}

// swiftlint:enable sorted_enum_cases
