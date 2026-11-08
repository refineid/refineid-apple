// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What the requester read as the custodian's first message (RAPP v26.11.8
/// §7.1 items 5 to 7).
public enum RappReadyOutcome: Equatable, Sendable {
  /// The frame failed authenticated decryption; the session is over and
  /// the pairing stays.
  case integrityFailure
  /// A `session.close` in its place, such as a revoking custodian's
  /// `pairingRevoked` (§4.6 item 2): release `echo`, the close that
  /// acknowledges it, when it could be sealed, then drop the link. The
  /// session is over.
  case peerClosed(RappCloseReason, echo: Data?)
  /// `session.ready` with the expected parameters and the custodian's
  /// current display name: record the name in the pair record (§4.3 item
  /// 4), release `hello`, the requester's `session.hello`, as the session's
  /// first message, and enter the established session.
  case verified(peerDisplayName: RappDisplayName, hello: Data)
  /// Anything else first, or mismatched parameters or name: release this
  /// sealed `protocol_violation` close, when there is one, wait for its echo
  /// with ``RappSessionBridge/receiveCloseEcho(bytes:)`` within the bound,
  /// and drop the link. The pairing stays (§10.1).
  case violationClosed(notice: Data?)
}
