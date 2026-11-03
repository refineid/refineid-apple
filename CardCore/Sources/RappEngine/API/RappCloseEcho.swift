// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One frame read while this endpoint waits for the echo of the
/// `session.close` it sent (RAPP v26.11.2 §7.1 item 7).
public enum RappCloseEcho: Equatable, Sendable {
  /// A `session.close` arrived: the peer's echo, or a close that crossed
  /// this endpoint's, carrying `reason`. It is never answered; act on a
  /// reason other than the one sent, then drop the link.
  case acknowledged(RappCloseReason)
  /// The frame failed authenticated decryption, or no close is awaited;
  /// drop the link.
  case ended
  /// Another message; it is ignored and the wait goes on.
  case ignored
}
