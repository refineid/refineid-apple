// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are ordered as silence grows, so the source reads in the order
// the decisions can occur.
// swiftlint:disable sorted_enum_cases

import Foundation

/// What a liveness poll asks the session to do.
internal enum LivenessDecision: Equatable {
  /// Nothing is due.
  case noAction
  /// Send a ping carrying this challenge.
  case sendPing(PingChallenge)
  /// Thirty seconds passed without any message; the session is over.
  case closeSession
  /// The tracker was already closed.
  case alreadyClosed
}

// swiftlint:enable sorted_enum_cases
