// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Turning one bridge action into the caller's commands.
  extension RappOperationDriver {
    /// Must be called only after the transport reports whether it released the
    /// corresponding frame; a failed release closes the session.
    public func frameReleased(_ release: FrameRelease, succeeded: Bool) -> [Command] {
      guard !closed else { return [] }
      guard succeeded else { return transportClosed() }
      switch release {
      case .noRelease:
        return []

      case .closeSession(let reason):
        closed = true
        return [.closed(reason)]
      }
    }

    /// Advances liveness with fresh challenge bytes: a ping after 5 seconds
    /// of silence, the session's end after 30 (RAPP v26.10.22 §8.3).
    public func pollLiveness() -> [Command] {
      guard !closed else { return [] }
      do {
        return try commands(
          bridge.pollLiveness(
            nowMs: clock.monotonicMilliseconds(), challenge: entropy.livenessChallenge()))
      } catch {
        return protocolFailure()
      }
    }

    /// Closes the session after the transport reported closure.
    public func transportClosed() -> [Command] {
      guard !closed else { return [] }
      return ending(bridge.closeSession(), as: .transportClosed)
    }

    /// Closes the session at local request.
    public func close() -> [Command] {
      guard !closed else { return [] }
      return ending(bridge.closeSession(), as: .localRequest)
    }

    /// Ends the session with an authenticated close carrying `reason`;
    /// the pairing stays unless `reason` is `pairingRevoked`.
    public func close(reason: RappCloseReason) -> [Command] {
      guard !closed else { return [] }
      return commands(bridge.closeWithReason(reason))
    }

    /// Tells the requester which card can answer now (§8.4).
    public func reportCardStatus(_ status: RappCardStatus) -> [Command] {
      guard !closed else { return [] }
      do {
        return try commands(bridge.reportCardStatus(status))
      } catch {
        return []
      }
    }

    internal func commands(_ action: RappBridgeAction) -> [Command] {
      switch action {
      case .sendFrame(let frame, _):
        return [.send(frame: frame, release: .noRelease)]

      case .sendClose(let frame, let reason, let ended):
        return closing(frame: frame, reason: reason, ended: ended)

      case .custodianStep(let operationID, let step, let descriptor):
        return [custodianCommand(step, operationID: operationID, operation: Operation(descriptor))]

      case .completed(let operationID, let result):
        return [.completed(operationID: operationID, result: result)]

      case .terminal(let operationID, let reason):
        return [.terminal(operationID: operationID, reason: reason)]

      case .progress(let operationID, let event):
        return [.progress(operationID: operationID, event: event)]

      case .cardStatus(let status):
        return [.cardStatus(status)]

      case .noAction:
        return []

      case .sessionClosed:
        return ending(action, as: closeReason(received: action))
      }
    }

    /// The command for the custodian's next step on its live operation.
    private func custodianCommand(
      _ step: RappCustodianStep, operationID: RappOperationIdentifier, operation: Operation
    ) -> Command {
      switch step {
      case .inspectPrerequisites:
        .inspectPrerequisites(operationID: operationID, operation: operation)

      case .awaitUserApproval:
        .awaitUserApproval(operationID: operationID, operation: operation)

      case .executeSafeRead:
        .executeSafeRead(operationID: operationID, operation: operation)

      case .executeCardCommand:
        .executeCardCommand(operationID: operationID, operation: operation)
      }
    }

    /// The commands for a `session.close` this endpoint sends: the operation
    /// that ended with the session, then the frame, whose release ends it.
    private func closing(
      frame: Data, reason: RappCloseReason, ended: RappEndedOperation?
    ) -> [Command] {
      let release: CloseReason =
        reason == .protocolViolation ? .protocolFailure : .terminalFrameReleased
      let send = Command.send(frame: frame, release: .closeSession(release))
      guard let ended else { return [send] }
      return [.operationEnded(ended), send]
    }

    /// The commands for a session that ended: the operation that ended with
    /// it, then the close.
    private func ending(_ action: RappBridgeAction, as reason: CloseReason) -> [Command] {
      closed = true
      guard case .sessionClosed(_, let ended?) = action else { return [.closed(reason)] }
      return [.operationEnded(ended), .closed(reason)]
    }

    /// Why the session closed when the peer closed it, or it ended without a
    /// notice.
    private func closeReason(received action: RappBridgeAction) -> CloseReason {
      guard case .sessionClosed(let reason?, _) = action else { return .transportClosed }
      switch reason {
      case .pairingRevoked:
        return .pairRevoked

      case .serviceWithdrawn:
        return .serviceWithdrawn

      default:
        return .peerClosed(reason)
      }
    }

    internal func protocolFailure() -> [Command] {
      guard !closed else { return [] }
      return ending(bridge.closeSession(), as: .protocolFailure)
    }
  }
#endif
