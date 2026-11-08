// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation
  import RappEngine

  /// A locked phone serves no credential action (RAPP v26.11.8 §8.2 item 3).
  extension RappPhoneProxyDispatcher {
    /// Waits for the holder to unlock before a credential action starts:
    /// true when it may start, false when its operation ended first.
    ///
    /// While the phone is locked the computer hears `waiting_for_unlock` and
    /// the lock screen names the computer and the PIN. The operation's
    /// deadline ends the wait through ``cancel(_:)``, as it ends a prompt.
    internal func awaitUnlock(
      operationID: RappOperationIdentifier,
      action: RappAuthorizationRequest.Action,
      coordinator: RappConnectionCoordinator
    ) async -> Bool {
      guard !sessionEnded else { return false }
      let turn = ServedSession.Turn(session: session, operation: operationID)
      let wait = RappUnlockWait(
        requestID: requestID(for: operationID), requester: requesterName, action: action)
      let inbox = inbox
      return await unlockGate.pass(turn) {
        #if DEBUG
          HolderTrace.say("phone locked: the credential action waits for the unlock")
        #endif
        try? await coordinator.reportProgress(operationID: operationID, event: .waitingForUnlock)
        await inbox.showUnlockWait(wait)
      } withdraw: {
        await inbox.withdrawUnlockWait(wait)
      }
    }

    /// Ends the wait of `operationID`, if it has one or is yet to start one.
    internal func endUnlockWait(_ operationID: RappOperationIdentifier) async {
      await unlockGate.end(ServedSession.Turn(session: session, operation: operationID))
    }
  }
#endif
