// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

// The cases are ordered as the engine emits them through an operation's life,
// so the source reads in the order the caller meets them.
// swiftlint:disable sorted_enum_cases

/// The bounded step the caller performs next (RAPP v26.11.2 §8).
///
/// Every outcome is data. The engine decides what must happen and the caller
/// performs it, so nothing here touches a card, a transport, or a screen. A
/// frame is sealed ciphertext in transit to the transport; nothing else
/// carries protocol bytes.
public enum RappBridgeAction: Equatable, Sendable {
  /// Release the frame on the session; it belongs to `operationId`'s
  /// operation when it names one.
  case sendFrame(Data, operationId: RappOperationIdentifier?)
  /// Release this endpoint's sealed `session.close` carrying `reason`, then
  /// wait for the peer's echo within the bound and drop the link (§7.1 item
  /// 7); the session is over and `endedOperation`, when present, ended with
  /// it (§8.1 item 3). Frames read while waiting go to
  /// ``RappOperationBridge/receiveFrame(bytes:nowMs:)``, which reports the
  /// echo as ``closeAcknowledged(reason:crossing:)``.
  case sendClose(Data, reason: RappCloseReason, endedOperation: RappEndedOperation?)
  /// Perform the custodian's next step for the described live operation.
  case custodianStep(RappOperationIdentifier, RappCustodianStep, RappOperationDescriptor)
  /// The requester's operation completed with its answer.
  case completed(RappOperationIdentifier, RappOperationResult)
  /// The requester's operation ended without completing, and why.
  case terminal(RappOperationIdentifier, RappTerminalReason)
  /// The custodian reported a change of the operation's state.
  case progress(RappOperationIdentifier, ProgressEvent)
  /// The custodian reported the card it holds and whether a card reader is
  /// connected to it (§8.4).
  case cardStatus(RappCardStatus)
  /// The requester named itself in its `session.hello`: record the name
  /// in the pair record where it differs (§4.3 item 4). Custodian only.
  case peerNamed(RappDisplayName)
  /// The peer closed the session with an authenticated `session.close`
  /// carrying `reason`: release `echo`, the close with the same reason that
  /// acknowledges it, then drop the link (§7.1 item 7). The session is over
  /// as for ``sessionClosed(reason:endedOperation:)``.
  case echoClose(Data, reason: RappCloseReason, endedOperation: RappEndedOperation?)
  /// The close this endpoint sent was acknowledged: the peer's echo, or,
  /// with `crossing`, a close carrying another reason that crossed it. Act
  /// on a crossing `reason`, never answer it, and drop the link.
  case closeAcknowledged(reason: RappCloseReason, crossing: Bool)
  /// Nothing to do.
  case noAction
  /// The session is over; the pairing stays. `reason` names the peer's
  /// authenticated close, if one ended it; on `pairingRevoked`, revoke the
  /// record and withdraw its identity (§4.6 item 4). `endedOperation`, when
  /// present, ended with the session (§8.1 item 3).
  case sessionClosed(reason: RappCloseReason?, endedOperation: RappEndedOperation?)
}

// swiftlint:enable sorted_enum_cases
