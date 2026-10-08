// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What approving a request leads to, decided by whether the action is
/// consequential.
internal enum ApprovalOutcome: Equatable {
  /// The in-flight journal entry is durable; take the one card command.
  case executeCardCommand
  case executeSafeRead(AuthorizedSafeRead)
}
