// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What the requester read as the custodian's first message (RAPP v26.10.29
/// §7.1 item 5).
public enum RappReadyOutcome: Equatable, Sendable {
  /// The frame failed authenticated decryption; the session is over and
  /// the pairing stays.
  case integrityFailure
  /// A `session.close` in its place, such as a revoking custodian's
  /// `pairingRevoked` (§4.6 item 2). The session is over.
  case peerClosed(RappCloseReason)
  /// `session.ready` with the expected parameters; enter the established
  /// session.
  case verified
  /// Anything else first, or mismatched parameters: release this sealed
  /// `protocol_violation` close, when there is one, and drop the link. The
  /// pairing stays (§10.1).
  case violationClosed(notice: Data?)
}
