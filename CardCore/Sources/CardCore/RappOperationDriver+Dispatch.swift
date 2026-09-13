// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  extension RappBridgeActionKind {
    /// Whether the step names an operation for the card or the holder.
    ///
    /// Exhaustive on purpose: a new kind must be routed here explicitly
    /// rather than falling silently into the session-level table.
    internal var isOperationStep: Bool {
      switch self {
      case .inspectPrerequisites, .awaitUserApproval, .executeSafeRead,
        .executeCardCommand, .terminal, .cancelled, .advisoryCancellation, .progress:
        true

      case .sendFrame, .resultAcknowledgment, .completed, .resultAcknowledged,
        .peerBusy, .peerUnknownOperation, .ignoredDuplicate, .noAction,
        .sessionClosed, .pairRevoked:
        false
      }
    }
  }

  /// Turning one bridge action into the caller's commands.
  extension RappOperationDriver {
    /// Must be called only after the transport reports whether it released the
    /// corresponding frame.
    ///
    /// A failed release classifies all in-flight work as a closed or ambiguous
    /// session through the Rust engine.
    public func frameReleased(_ release: FrameRelease, succeeded: Bool) -> [Command] {
      guard !closed else { return [] }
      guard succeeded else { return transportClosed() }

      do {
        switch release {
        case .noRelease:
          return []

        case .resultAcknowledgment(let operationID):
          let result = try bridge.acknowledgmentReleased(operationId: operationID)
          return [.completed(operationID: operationID, result: Result(result))]

        case .closeSession:
          closed = true
          return [.closed(revokedWhileClosing ? .pairRevoked : .terminalFrameReleased)]
        }
      } catch {
        return protocolFailure()
      }
    }

    /// Advances authenticated liveness with fresh challenge bytes and the
    /// caller-generated jitter.
    public func pollLiveness(jitterMilliseconds: Int64) -> [Command] {
      guard !closed else { return [] }
      do {
        return try commands(
          bridge.pollLiveness(
            nowMs: clock.monotonicMilliseconds(),
            challenge: entropy.livenessChallenge(),
            jitterMs: jitterMilliseconds
          ))
      } catch {
        return protocolFailure()
      }
    }

    /// Closes the session after the transport reported closure.
    ///
    /// A pairing revoked while this driver lived outranks the transport
    /// as the reason: the close is the revocation's, however the frames
    /// stopped flowing.
    public func transportClosed() -> [Command] {
      guard !closed else { return [] }
      closed = true
      _ = bridge.closeSession()
      return [.closed(revokedWhileClosing ? .pairRevoked : .transportClosed)]
    }

    /// Closes the session at local request.
    public func close() -> [Command] {
      guard !closed else { return [] }
      closed = true
      _ = bridge.closeSession()
      return [.closed(revokedWhileClosing ? .pairRevoked : .localRequest)]
    }

    /// Ends the session and the pairing because the card can no longer
    /// be served.
    public func revokeBecauseCardUnavailable() -> [Command] {
      guard !closed else { return [] }
      do {
        return try commands(bridge.cardUnavailableClose())
      } catch {
        return close()
      }
    }

    internal func commands(_ action: RappBridgeAction) throws -> [Command] {
      if action.revokesPairing {
        // The revocation is written before any notice frame is released,
        // so the pairing is dead even if the notice never arrives. The
        // close is reported as a revocation either way - the protocol
        // event happened and the app must fail-stop - but a refused
        // write is retried once here and again on the next incident,
        // not silently forgotten.
        revokedWhileClosing = true
        revokePairDurably()
      }
      if let frame = action.frame {
        return try scheduled([.send(frame: frame, release: release(for: action))], for: action)
      }
      if action.kind.isOperationStep {
        return try stepCommands(action)
      }
      return try lifecycleCommands(action)
    }

    /// Writes the revocation the vault must hold, retrying one refusal.
    ///
    /// A pairing already revoked answers the second attempt as done; a
    /// vault refusing both writes leaves the record for the next
    /// incident, while the in-memory fail-stop still ends this
    /// connection.
    private func revokePairDurably() {
      let revokedAt = clock.wallMilliseconds()
      if (try? vault.revokeDeviceOnly(pairId: pairID, revokedAtMs: revokedAt)) != nil {
        return
      }
      try? vault.revokeDeviceOnly(pairId: pairID, revokedAtMs: revokedAt)
    }

    /// The release token the transport must return for one frame.
    private func release(for action: RappBridgeAction) throws -> FrameRelease {
      if action.kind == .resultAcknowledgment {
        guard let operationID = action.operationId else {
          throw LocalError.missingOperationIdentifier
        }
        return .resultAcknowledgment(operationID: operationID)
      }
      return action.closeSessionAfterSend ? .closeSession : .noRelease
    }

    /// Commands for the steps that name an operation.
    private func stepCommands(_ action: RappBridgeAction) throws -> [Command] {
      let operationID = action.operationId
      switch action.kind {
      case .inspectPrerequisites:
        return scheduled(
          [try operationCommand(action, operationID: operationID, kind: .inspect)],
          for: action
        )

      case .awaitUserApproval:
        return scheduled(
          [try operationCommand(action, operationID: operationID, kind: .approval)],
          for: action
        )

      case .executeSafeRead:
        return scheduled(
          [try operationCommand(action, operationID: operationID, kind: .safeRead)],
          for: action
        )

      case .executeCardCommand:
        return scheduled(
          [try operationCommand(action, operationID: operationID, kind: .cardCommand)],
          for: action
        )

      case .terminal, .cancelled:
        return scheduled(
          [
            .terminal(
              operationID: operationID,
              state: action.terminalState,
              reason: action.terminalReason.map(TerminalReason.init)
            )
          ], for: action)

      case .advisoryCancellation:
        return scheduled([.advisoryCancellation(operationID: operationID)], for: action)

      case .progress:
        guard let operationID, let event = action.progressEvent else {
          throw LocalError.missingOperationIdentifier
        }
        return scheduled([.progress(operationID: operationID, event: event)], for: action)

      case .sendFrame, .resultAcknowledgment, .completed, .resultAcknowledged,
        .peerBusy, .peerUnknownOperation, .ignoredDuplicate, .noAction,
        .sessionClosed, .pairRevoked:
        throw LocalError.wrongPhase
      }
    }

    /// Commands for the session-level outcomes.
    private func lifecycleCommands(_ action: RappBridgeAction) throws -> [Command] {
      let operationID = action.operationId
      switch action.kind {
      case .resultAcknowledged:
        return scheduled([.operationFinished(operationID: operationID)], for: action)

      case .peerBusy:
        return scheduled([.peerBusy(operationID: operationID)], for: action)

      case .peerUnknownOperation:
        return scheduled([.peerUnknownOperation(operationID: operationID)], for: action)

      case .sessionClosed:
        closed = true
        return [.closed(.protocolFailure)]

      case .pairRevoked:
        closed = true
        return [.closed(.pairRevoked)]

      case .sendFrame, .resultAcknowledgment:
        throw LocalError.missingFrame

      case .completed:
        throw LocalError.wrongPhase

      case .ignoredDuplicate, .noAction:
        return scheduled([], for: action)

      case .inspectPrerequisites, .awaitUserApproval, .executeSafeRead,
        .executeCardCommand, .terminal, .cancelled, .advisoryCancellation, .progress:
        throw LocalError.wrongPhase
      }
    }

    private func scheduled(
      _ commands: [Command],
      for action: RappBridgeAction
    ) -> [Command] {
      guard let deadline = action.nextPollAtMs else { return commands }
      return commands + [.scheduleLiveness(atMonotonicMilliseconds: deadline)]
    }

    private func operationCommand(
      _ action: RappBridgeAction,
      operationID: Data?,
      kind: OperationCommandKind
    ) throws -> Command {
      guard let operationID else { throw LocalError.missingOperationIdentifier }
      guard let descriptor = action.operation else { throw LocalError.missingOperation }
      let operation = Operation(descriptor)
      switch kind {
      case .inspect:
        return .inspectPrerequisites(operationID: operationID, operation: operation)

      case .approval:
        return .awaitUserApproval(operationID: operationID, operation: operation)

      case .safeRead:
        return .executeSafeRead(operationID: operationID, operation: operation)

      case .cardCommand:
        return .executeCardCommand(operationID: operationID, operation: operation)
      }
    }

    internal func protocolFailure() -> [Command] {
      guard !closed else { return [] }
      closed = true
      _ = bridge.closeSession()
      return [.closed(.protocolFailure)]
    }
  }
#endif
