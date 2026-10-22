// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are ordered as the operation proceeds, so the source reads in
// the order the stages can occur.
// swiftlint:disable sorted_enum_cases

import Foundation

/// The phase one operation has reached.
internal enum AuthorizationStage: Equatable {
  /// Admitted; the reads that precede consent have not completed.
  case requested
  /// The consent view may be shown; only an action that needs the holder's
  /// authorization comes here.
  case awaitingConsent
  /// A registered read is running.
  case executingSafeRead
  /// The one card command has been handed to the card adapter.
  case executing
  /// The result is out.
  case terminal
}

// swiftlint:enable sorted_enum_cases
