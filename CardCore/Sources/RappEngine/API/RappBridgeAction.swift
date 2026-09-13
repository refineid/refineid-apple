// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The bounded step the caller performs next.
///
/// The kind names the step; the other fields carry only what that step needs.
public struct RappBridgeAction: Equatable, Sendable {
  /// What the caller does next.
  public var kind: RappBridgeActionKind
  /// The operation this step belongs to, when it belongs to one.
  public var operationId: Data?
  /// What the holder is being asked to allow, when consent is being sought.
  public var operation: RappOperationDescriptor?
  /// The sealed frame to release, when the step releases one.
  public var frame: Data?
  /// The journaled state an ended operation reached.
  public var terminalState: String?
  /// Why an operation ended without an answer.
  public var terminalReason: RappTerminalReason?
  /// Close the session once the accompanying frame has been released.
  public var closeSessionAfterSend: Bool
  /// Durably revoke the stored pairing before releasing any frame.
  ///
  /// Set for the conditions whose pairing effect the specification's
  /// failure taxonomy names as revocation: a rejected credential, an
  /// authenticated protocol violation, and a peer's authenticated
  /// revocation notice. A card leaving is not among them.
  public var revokesPairing: Bool
  /// Monotonic time of the next required liveness poll.
  public var nextPollAtMs: UInt64?
  /// Advisory progress event reported by peer.
  public var progressEvent: ProgressEvent?

  /// Describes one step, carrying only what that step needs.
  public init(
    kind: RappBridgeActionKind,
    operationId: Data? = nil,
    operation: RappOperationDescriptor? = nil,
    frame: Data? = nil,
    terminalState: String? = nil,
    terminalReason: RappTerminalReason? = nil,
    closeSessionAfterSend: Bool = false,
    revokesPairing: Bool = false,
    nextPollAtMs: UInt64? = nil,
    progressEvent: ProgressEvent? = nil
  ) {
    self.kind = kind
    self.operationId = operationId
    self.operation = operation
    self.frame = frame
    self.terminalState = terminalState
    self.terminalReason = terminalReason
    self.closeSessionAfterSend = closeSessionAfterSend
    self.revokesPairing = revokesPairing
    self.nextPollAtMs = nextPollAtMs
    self.progressEvent = progressEvent
  }
}
