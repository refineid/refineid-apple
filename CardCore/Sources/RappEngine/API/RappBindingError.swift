// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

// The case names and their order are the ones the interface has always used
// and callers already catch by name.
// swiftlint:disable sorted_enum_cases identifier_name
// swift-format-ignore: AlwaysUseLowerCamelCase

/// A failure crossing the engine's public boundary.
///
/// The cases name what the caller did, not where the engine noticed, so a
/// caller can tell a malformed argument from a call made in the wrong phase.
/// They are deliberately coarse: protocol internals and secrets never become
/// interface strings.
public enum RappBindingError: Error, Equatable, Hashable, LocalizedError, Sendable {
  /// Caller-provided bytes or registry values were invalid.
  case InvalidInput
  /// The call was not legal in the current protocol phase.
  case WrongPhase
  /// The one-use pairing offer reached its monotonic deadline.
  case OfferExpired
  /// Authenticated protocol or cryptographic processing failed.
  case ProtocolFailure
  /// Local state could not be read or written.
  case LocalStateFailure
  /// No stored pairing carries the identifier.
  case PairNotFound
  /// Three pairing attempts failed against one offer; the offer is destroyed
  /// (RAPP v26.10.9 §3.3).
  case AttemptsExhausted

  /// The case name, for a caller that logs or displays the failure.
  public var errorDescription: String? {
    String(reflecting: self)
  }
}

// swiftlint:enable sorted_enum_cases identifier_name
