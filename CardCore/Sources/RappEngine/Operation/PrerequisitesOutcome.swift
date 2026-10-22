// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What follows once an operation has the card and its prerequisite reads
/// are done (RAPP v26.10.21 §8.2 items 3 and 6).
internal enum PrerequisitesOutcome: Equatable {
  /// Show the consent view and wait for the holder.
  case awaitConsent
  /// Execute this read and answer directly with a result; no consent.
  case executeSafeRead(AuthorizedSafeRead)
}
