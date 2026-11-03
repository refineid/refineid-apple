// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A rejected operation construction or parse.
internal enum CardOperationError: Error, Equatable {
  case invalidDisplayContext
  case invalidField(field: String)
  case invalidIdentifier
  case invalidLifetime
  case keyAlgorithmMismatch
  case operationMismatch
  /// The request of a package, with every file it holds, does not fit one
  /// frame (RAPP v26.11.2 §9.3).
  case packageTooLarge
  case profileActionMismatch
  case unexpectedField
  case unknownAction
  case unknownProfile
  case wrongDigestLength
}
