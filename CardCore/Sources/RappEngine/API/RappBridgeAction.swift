// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

// The cases are ordered as the engine emits them through an operation's life,
// so the source reads in the order the caller meets them.
// swiftlint:disable sorted_enum_cases

/// The bounded step the caller performs next (RAPP v26.10.22 §8).
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
  /// drop the link; the session is over and `endedOperation`, when present,
  /// ended with it (§8.1 item 3).
  case sendClose(Data, reason: RappCloseReason, endedOperation: RappEndedOperation?)
  /// Perform the custodian's next step for the described live operation.
  case custodianStep(RappOperationIdentifier, RappCustodianStep, RappOperationDescriptor)
  /// The requester's operation completed with its answer.
  case completed(RappOperationIdentifier, RappOperationResult)
  /// The requester's operation ended without completing, and why.
  case terminal(RappOperationIdentifier, RappTerminalReason)
  /// The custodian reported a change of the operation's state.
  case progress(RappOperationIdentifier, ProgressEvent)
  /// The custodian reported which card it can serve now (§8.4).
  case cardStatus(RappCardStatus)
  /// Nothing to do.
  case noAction
  /// The session is over; the pairing stays. `reason` names the peer's
  /// authenticated close, if one ended it; on `pairingRevoked`, revoke the
  /// record and withdraw its identity (§4.6 item 4). `endedOperation`, when
  /// present, ended with the session (§8.1 item 3).
  case sessionClosed(reason: RappCloseReason?, endedOperation: RappEndedOperation?)
}

// swiftlint:enable sorted_enum_cases
