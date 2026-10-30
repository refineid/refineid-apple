// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import RappEngine

  /// Why a requester operation ended without a response.
  public enum RappRequesterClientError: Error, Sendable, Equatable {
    case noActivePair
    case noSelectedPair

    /// No paired device answered the search. Nothing was reached, so
    /// nothing about the card was learned.
    case peerNotFound
    case protocolFailure
    case terminal(RappTerminalReason)
    case timedOut
    case transport
    case unexpectedResult
  }
#endif
