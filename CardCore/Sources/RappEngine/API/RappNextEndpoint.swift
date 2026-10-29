// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The endpoint a requester opens next (RAPP v26.10.29 §4.2, "Trying Each
/// Custodian in Pairing Mode" item 1).
public enum RappNextEndpoint<Endpoint: Equatable & Sendable>: Equatable, Sendable {
  /// No endpoint is left to open, or the connection limit is reached: wait
  /// for discovery to find another.
  case exhausted
  /// Only endpoints waiting out a busy answer are left: ask again at this
  /// platform monotonic time, showing nothing meanwhile.
  case notBefore(monotonicMs: UInt64)
  /// Open a pairing connection to this endpoint now.
  case open(Endpoint)

  internal init(_ next: NextEndpoint<Endpoint>) {
    switch next {
    case .exhausted:
      self = .exhausted

    case .notBefore(let monotonicMs):
      self = .notBefore(monotonicMs: monotonicMs)

    case .open(let endpoint):
      self = .open(endpoint)
    }
  }
}
