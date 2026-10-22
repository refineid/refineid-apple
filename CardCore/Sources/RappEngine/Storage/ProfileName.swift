// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are transcribed in the order the specification registers them,
// so the source reads line for line against the document.
// swiftlint:disable sorted_enum_cases

import Foundation

/// Credential profiles the registry admits.
internal enum ProfileName: String, CaseIterable, Equatable {
  case cardStatus = "fi.refineid.card-status"
  case authentication = "fi.refineid.authentication"
  case documentSigning = "fi.refineid.document-signing"
}

// swiftlint:enable sorted_enum_cases
