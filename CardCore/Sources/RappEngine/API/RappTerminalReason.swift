// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are ordered as the specification's failure table lists them, so
// the source reads line for line against the document.
// swiftlint:disable sorted_enum_cases

/// Why an operation ended without an answer.
public enum RappTerminalReason: Sendable {
  case userDenied
  case requestExpired
  case cancelled
  case requestInvalidOrUnsupported
  case retryPolicyRefused
  case credentialRejected
  case cardRemovedBeforeTransmit
  case cardCompletionAmbiguous
  /// The card refused the credential and attempts remain; the pairing stays.
  case invalidCredential
}

// swiftlint:enable sorted_enum_cases
