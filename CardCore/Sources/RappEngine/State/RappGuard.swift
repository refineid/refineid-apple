// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are transcribed in the order the formal model lists them, so the
// tables read line for line against the document. Alphabetising them would
// break the correspondence the bidirectional conformance test protects.
// swiftlint:disable sorted_enum_cases

/// A condition a transition rule requires.
///
/// Raw values are the formal model's guard names, and the model carries each
/// one's prose definition.
internal enum RappGuard: String, CaseIterable, Sendable {
  case userInitiated = "user_initiated"
  case localUserAction = "local_user_action"
  case transcriptMatches = "transcript_matches"
  case grantedSetsEqual = "granted_sets_equal"
  case initiationPermitted = "initiation_permitted"
  case pairingRouted = "pairing_routed"
  case readyParametersMatch = "ready_parameters_match"
  case untriedPairingCandidate = "untried_pairing_candidate"
}

// swiftlint:enable sorted_enum_cases
