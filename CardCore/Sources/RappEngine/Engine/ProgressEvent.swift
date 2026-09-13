// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Advisory progress event during an authenticated operation.
public enum ProgressEvent: String, Sendable, Equatable, CaseIterable {
  case cardWaitEnded = "card_wait_ended"
  case unknown = "unknown"
  case waitingForCard = "waiting_for_card"

  /// Initializes a progress event from its wire representation, mapping unrecognized events to `.unknown`.
  public init(wireValue: String) {
    self = Self(rawValue: wireValue) ?? .unknown
  }
}
