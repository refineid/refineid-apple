// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// Why a session could not be established or continued.
///
/// No case revokes the pairing (RAPP v26.10.21 §10.1): a frame that fails
/// authenticated decryption and one that decrypted and broke the protocol
/// both close only the session.
internal enum SessionError: Error, Equatable {
  case closed
  case duplicateReady
  case integrityFailure
  case message(MessageFieldError)
  case noise
  case readyIncomplete
  case roleViolation
  /// The stored pairing was never confirmed by both endpoints; it opens no
  /// session (§4.3 item 4).
  case storageUnconfirmed
  case unexpectedMessage
  /// The connection's transport profile is not registered (§2.2).
  case unregisteredTransport
}
