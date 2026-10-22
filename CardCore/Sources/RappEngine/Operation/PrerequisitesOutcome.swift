// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What follows once an operation has the card and its prerequisite reads
/// are done (RAPP v26.10.22 §8.2 items 3 and 6).
internal enum PrerequisitesOutcome: Equatable {
  /// Take the PIN, prompting the holder when it is not held.
  case awaitConsent
  /// Execute this read and answer directly with a result; the holder is
  /// asked nothing.
  case executeSafeRead(AuthorizedSafeRead)
}
