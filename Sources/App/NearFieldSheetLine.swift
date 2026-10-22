// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What the near-field sheet says about the operation running in it.
internal enum NearFieldSheetLine: Equatable, Sendable {
  /// The card is in the field and an operation runs on it.
  case cardFound

  /// The operation ended without the card's result.
  case cardNotRead

  /// The operation has the card's result.
  case cardRead
}
