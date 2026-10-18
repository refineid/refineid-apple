// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// Why a session could not be established or continued.
///
/// The two failure kinds are kept apart deliberately: an integrity failure is
/// not attributable to the peer and ends only the session, while an
/// authenticated violation ends the pairing.
internal enum SessionError: Error, Equatable {
  case closed
  case duplicateReady
  case integrityFailure
  case message(MessageFieldError)
  case noise

  /// An authenticated violation. The caller must end the stored pairing.
  case pairingMustEnd(cause: SessionViolation)
  case parameterMismatch
  case readyIncomplete
  case roleViolation
  /// The stored pairing was never confirmed by both endpoints; it opens no
  /// session (RAPP v26.10.18 §4.3 item 4).
  case storageUnconfirmed
  case unexpectedMessage
}
