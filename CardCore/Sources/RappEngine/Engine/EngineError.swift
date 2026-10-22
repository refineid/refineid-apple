// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A refused engine step.
internal enum EngineError: Error, Equatable {
  /// Authenticated peer traffic broke the protocol; the session closes.
  case authenticatedProtocolViolation(EngineViolation)
  /// The local caller reused an identifier the session has used.
  case duplicateLocalOperationIdentifier
  /// The local caller asked for a transition the machine does not define.
  case invalidLocalTransition
  /// A locally produced value failed its own validation.
  case invalidLocalValue
  /// Another operation of the session is live.
  case liveOperation
  /// The local caller named an operation this session does not hold.
  case unknownLocalOperation
}
