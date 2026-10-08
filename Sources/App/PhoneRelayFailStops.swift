// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  #if DEBUG
    import Darwin
  #endif

  /// Classifies which connection events demand explicit user action before
  /// the phone proxy reconnects.
  internal enum PhoneRelayFailStops {
    /// Whether the event is a fail-stop that suspends automatic
    /// reconnection until the holder acts.
    internal static func requireExplicitUserAction(
      _ event: RappConnectionCoordinator.Event
    ) -> Bool {
      switch event {
      case .terminal(_, _, let reason):
        switch reason {
        case .credentialRejected, .cardCompletionAmbiguous:
          return true

        case .userDenied, .requestExpired, .cancelled,
          .requestInvalidOrUnsupported, .retryPolicyRefused,
          .cardRemovedBeforeTransmit, .invalidCredential, nil:
          return false
        }

      case .closed(let reason):
        #if DEBUG
          print("[PhoneRelayFailStops] session closed reason: \(reason)")
          fflush(stdout)
        #endif
        switch reason {
        case .handshake(.pairRevoked), .operation(.pairRevoked):
          return true

        case .handshake(.protocolFailure), .operation(.protocolFailure),
          .handshake(.localRequest), .handshake(.transportClosed),
          .operation(.localRequest), .operation(.transportClosed),
          .operation(.terminalFrameReleased), .transportFailure,
          .localRequest:
          return false
        }

      case .established, .inspectPrerequisites, .awaitUserApproval,
        .executeSafeRead, .executeCardCommand, .completed,
        .operationFinished, .peerBusy,
        .peerUnknownOperation, .progress:
        return false
      }
    }
  }
#endif
