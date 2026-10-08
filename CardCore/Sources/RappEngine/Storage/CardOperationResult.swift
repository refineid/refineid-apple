// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are transcribed in the order the specification registers them,
// so the source reads line for line against the document.
// swiftlint:disable sorted_enum_cases

import Foundation

/// Typed output of one completed card operation.
internal enum CardOperationResult: Equatable {
  case inspection(CardInspection)
  case identity(CardIdentity)
  case certificate(Data, cardSerial: String? = nil)
  case signature(Data)
}

// swiftlint:enable sorted_enum_cases
