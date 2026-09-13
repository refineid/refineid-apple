// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Advisory progress event during an authenticated operation.
public enum ProgressEvent: String, Sendable, Equatable, CaseIterable {
  case cardWaitEnded = "card_wait_ended"
  case waitingForCard = "waiting_for_card"
}
