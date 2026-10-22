// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are ordered as the specification's error table lists them, so
// the source reads line for line against the document.
// swiftlint:disable sorted_enum_cases

/// Why an operation ended without completing: the registered error name
/// (RAPP v26.10.22 §10.3).
public enum RappTerminalReason: Sendable, Equatable, CaseIterable {
  /// Another operation of the session was live.
  case busy
  /// The identifier was already used on the session.
  case duplicateOperation
  /// The lifetime was zero.
  case invalidLifetime
  /// The deadline passed before the card was commanded.
  case operationExpired
  /// The pairing does not grant the profile.
  case unauthorized
  /// A parameter is not supported.
  case unsupportedParameter
  /// The holder declined.
  case userCancelled
  /// The card's remaining attempts are reserved for its issuer's software.
  case retryFloor
  /// The card did not answer.
  case cardError
  /// The custodian could not carry the operation out.
  case operationFailed
}

// swiftlint:enable sorted_enum_cases
