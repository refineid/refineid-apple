// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore

  /// Typed failure returned by ``WebEidCardRunner`` during card inspection or execution.
  internal enum WebEidCardFailure: Error, Equatable, Sendable {
    case cardError
    case certificateMismatch
    case certificateUnavailable
    case invalidated
    case invalidPinEntry
    case noCard
    case pin2RequiresChangeBeforeSigning
    case pinBlocked
    case pinRejected(remaining: RetryCount)
    case retryFloorRefused(verdict: RetryFloorVerdict, remaining: RetryCount?)
    case unsupportedAlgorithm
  }

#endif
