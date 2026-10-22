// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are transcribed in the order the formal model lists them, so the
// tables read line for line against the document.
// swiftlint:disable sorted_enum_cases

/// The role a transition rule applies to (RAPP v26.10.22 formal state model,
/// `semantics.roles`).
internal enum RuleRole: String, CaseIterable, Sendable {
  case requester = "requester"
  case custodian = "custodian"
  case both = "both"

  /// Whether an endpoint in `role` implements rules carrying this value.
  internal func includes(_ role: EndpointRole) -> Bool {
    switch self {
    case .both:
      true

    case .requester:
      role == .requester

    case .custodian:
      role == .proxy
    }
  }
}

// swiftlint:enable sorted_enum_cases
