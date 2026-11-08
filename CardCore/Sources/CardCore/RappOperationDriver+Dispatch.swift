// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Turning one bridge action into the caller's commands.
  extension RappOperationDriver {
    /// The session's end for an authenticated close the peer sent.
    private static func closeReason(peer reason: RappCloseReason) -> CloseReason {
      switch reason {
      case .pairingRevoked:
        .pairRevoked

      case .serviceWithdrawn:
        .serviceWithdrawn

      default:
        .peerClosed(reason)
      }
    }

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
        echoReason = reason
        return [.awaitCloseEcho]
      }
    }

    /// Ends the wait for the echo of this endpoint's close once its bound
    /// passed; the session ends as the close said (§7.1 item 7).
    public func echoWaitEnded() -> [Command] {
      guard let echoReason else { return [] }
      self.echoReason = nil
      _ = bridge.closeSession()
      return [.closed(echoReason)]
    }

    /// One frame read while this endpoint waits for the echo of its close:
    /// the echo, or a crossing close whose reason this endpoint acts on,
    /// ends the session; anything else is ignored.
    internal func receiveWhileAwaitingEcho(_ frame: Data, sent: CloseReason) -> [Command] {
      switch bridge.receiveFrame(bytes: frame, nowMs: clock.monotonicMilliseconds()) {
      case .closeAcknowledged(let reason, let crossing):
        echoReason = nil
        // Only the echo, or the peer's own revocation crossing it, says the
        // peer heard this endpoint's close; another reason crossing it does
        // not (RAPP v26.11.2 §7.1 item 7).
        ownCloseEchoed = !crossing || reason == .pairingRevoked
        return [.closed(crossing ? Self.closeReason(peer: reason) : sent)]

      case .sessionClosed:
        echoReason = nil
        return [.closed(sent)]

      default:
        return []
      }
    }

    /// Advances liveness with fresh challenge bytes: a ping after 5 seconds
    /// of silence, the session's end after 30 (RAPP v26.11.2 §8.3).
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
      if echoReason != nil { return echoWaitEnded() }
      guard !closed else { return [] }
      return ending(bridge.closeSession(), as: .transportClosed)
    }

    /// Closes the session at local request.
    public func close() -> [Command] {
      if echoReason != nil { return echoWaitEnded() }
      guard !closed else { return [] }
      return ending(bridge.closeSession(), as: .localRequest)
    }

    /// Ends the session with an authenticated close carrying `reason`;
    /// the pairing stays unless `reason` is `pairingRevoked`.
    public func close(reason: RappCloseReason) -> [Command] {
      guard !closed else { return [] }
      return commands(bridge.closeWithReason(reason))
    }

    /// Tells the requester which card this custodian holds and whether a
    /// contact card reader is connected to it (§8.4).
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

      case .completed, .terminal, .progress, .cardStatus, .peerNamed:
        return [reported(action)].compactMap(\.self)

      case .echoClose(let frame, let reason, let ended):
        return echoing(frame, reason: reason, ended: ended)

      case .noAction, .closeAcknowledged:
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
        reason == .protocolViolation ? .protocolViolation : .terminalFrameReleased
      let send = Command.send(frame: frame, release: .closeSession(release))
      guard let ended else { return [send] }
      return [.operationEnded(ended), send]
    }

    /// The command reporting what the peer said, for the actions that only
    /// report.
    private func reported(_ action: RappBridgeAction) -> Command? {
      switch action {
      case .completed(let operationID, let result):
        .completed(operationID: operationID, result: result)

      case .terminal(let operationID, let reason):
        .terminal(operationID: operationID, reason: reason)

      case .progress(let operationID, let event):
        .progress(operationID: operationID, event: event)

      case .cardStatus(let status):
        .cardStatus(status)

      case .peerNamed(let name):
        .peerNamed(name)

      default:
        nil
      }
    }

    /// The commands for the peer's close: the operation that ended with the
    /// session, then the echo, then the close (§7.1 item 7).
    private func echoing(
      _ frame: Data, reason: RappCloseReason, ended: RappEndedOperation?
    ) -> [Command] {
      closed = true
      let send = Command.send(frame: frame, release: .noRelease)
      let close = Command.closed(Self.closeReason(peer: reason))
      guard let ended else { return [send, close] }
      return [.operationEnded(ended), send, close]
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
      return Self.closeReason(peer: reason)
    }

    internal func protocolFailure() -> [Command] {
      guard !closed else { return [] }
      return ending(bridge.closeSession(), as: .protocolFailure)
    }
  }
#endif
