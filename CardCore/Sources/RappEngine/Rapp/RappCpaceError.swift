// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Errors raised during CPace execution.
public enum RappCpaceError: Error, Equatable, Sendable {
  /// The peer's confirmation tag did not verify.
  case confirmationTagMismatch
  /// The derived generator is the group identity; the offer must be abandoned.
  case identityGenerator
  case identitySharedPoint
  case invalidCode
  case invalidPoint
  case invalidScalar
  case malformedFrame
}
