// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// An authenticated protocol violation seen by either operation engine.
///
/// Every case closes the session with a sealed `protocol_violation` close;
/// none revokes the pairing (RAPP v26.10.29 §10.1).
internal enum EngineViolation: Equatable {
  /// The requester sent a message only a custodian sends.
  case custodianOnlyMessage
  /// A result does not answer the live request.
  case invalidResult
  /// The custodian sent a message only a requester sends.
  case requesterOnlyMessage
}
