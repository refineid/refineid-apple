// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Why a received frame could not be turned into a message.
///
/// The two cases are kept apart because only the first can still be
/// answered: a frame that decrypted and broke the protocol is answered with
/// a sealed `protocol_violation` close, while one that fails to decrypt
/// closes the session silently (RAPP v26.10.22 §10.1).
internal enum RappOpenFailure: Error, Equatable {
  /// Decrypted, then nonconforming.
  case authenticatedProtocolViolation

  /// Failed authenticated decryption.
  case sessionIntegrityFailure
}
