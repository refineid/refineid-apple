// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Progress event during an authenticated operation (RAPP v26.10.18 §7.1).
public enum ProgressEvent: String, Sendable, Equatable, CaseIterable {
  case cardWaitEnded = "card_wait_ended"
  /// The custodian's consent view is on screen (§8.2 item 3).
  case consentShown = "consent_shown"
  case unknown = "unknown"
  case waitingForCard = "waiting_for_card"

  /// Initializes a progress event from its wire representation, mapping unrecognized events to `.unknown`.
  public init(wireValue: String) {
    self = Self(rawValue: wireValue) ?? .unknown
  }
}
