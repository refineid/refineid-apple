// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Errors raised during CPace execution.
public enum RappCpaceError: Error, Equatable, Sendable {
  case identitySharedPoint
  case invalidCode
  case invalidPoint
  case invalidScalar
  case malformedFrame
}
