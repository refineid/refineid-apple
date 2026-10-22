// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What a warm near field tells its owner, for the sounds, the trace and
/// the development error display.
internal enum NearFieldEvent: Sendable {
  /// The field ended for `ending`, with its slot in the state named
  /// `slotState`.
  case ended(CardSessionHold.Ending, slotState: String)

  /// No field opened, for `failure`.
  case notOpened(any Error)

  /// A new field opened with the card in it.
  case opened

  /// An operation ended; `succeeded` says it has the card's result.
  case operationFinished(succeeded: Bool)

  /// An operation started on the card.
  case operationStarted

  /// An operation found the field open and runs on it.
  case reused
}
