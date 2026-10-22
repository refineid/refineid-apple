// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG
  import CardCore
  import RappEngine

  extension RappConnectionCoordinator.CloseReason {
    private static func devErrorName(handshake reason: RappSessionDriver.CloseReason) -> String? {
      switch reason {
      case .localRequest, .pairRevoked, .revocationNoticeDelivered:
        nil

      case .transportClosed:
        "transport closed before the session was up"

      case .protocolFailure:
        "handshake protocol failure"

      case .peerClosed(let close):
        Self.isFailure(close) ? "peer refused the session: \(close.rawValue)" : nil
      }
    }

    private static func devErrorName(
      operation reason: RappOperationDriver.CloseReason,
      midOperation: Bool
    ) -> String? {
      switch reason {
      case .localRequest, .pairRevoked, .serviceWithdrawn, .terminalFrameReleased:
        nil

      case .transportClosed:
        midOperation ? "transport closed mid-operation" : nil

      case .protocolFailure:
        "protocol failure"

      case .peerClosed(let close):
        Self.isFailure(close) ? "peer closed the session: \(close.rawValue)" : nil
      }
    }

    /// Whether a registered close reason names a failure rather than an
    /// ordinary end.
    private static func isFailure(_ close: RappCloseReason) -> Bool {
      switch close {
      case .cardUnavailable, .policy, .protocolViolation:
        true

      case .complete, .normal, .pairingRevoked, .serviceWithdrawn, .shutdown, .userDisconnect:
        false
      }
    }

    /// The close as the development error display names it, or nil when the
    /// session ended the ordinary way.
    ///
    /// A transport that closes once the session is up is an ordinary end:
    /// a requester's app and token extension hand one session over, and a
    /// phone leaves. It is a failure only while an operation still runs on
    /// it. A transport that closes before the session is up never is
    /// ordinary.
    internal func devErrorName(midOperation: Bool) -> String? {
      switch self {
      case .localRequest:
        nil

      case .transportFailure:
        "transport failure"

      case .handshake(let reason):
        Self.devErrorName(handshake: reason)

      case .operation(let reason):
        Self.devErrorName(operation: reason, midOperation: midOperation)
      }
    }
  }
#endif
