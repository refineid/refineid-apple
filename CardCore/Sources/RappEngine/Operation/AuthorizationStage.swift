// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are ordered as the operation proceeds, so the source reads in
// the order the stages can occur.
// swiftlint:disable sorted_enum_cases

import Foundation

/// The phase one operation has reached.
internal enum AuthorizationStage: Equatable {
  /// Admitted; the reads that precede the PIN have not completed.
  case requested
  /// The custodian takes the PIN: it prompts for one it does not hold, and
  /// entering it is the holder's consent (RAPP v26.10.22 §8.2 item 3); only
  /// an action that needs a PIN comes here.
  case awaitingConsent
  /// A registered read is running.
  case executingSafeRead
  /// The one card command has been handed to the card adapter.
  case executing
  /// The result is out.
  case terminal
}

// swiftlint:enable sorted_enum_cases
