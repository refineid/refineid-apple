// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Turning an engine dispatch into the caller's next step.
extension RappOperationBridge {
  /// Classifies one typed message on whichever side runs here.
  ///
  /// A message the engine refuses as an authenticated protocol violation closes
  /// the session with a sealed `protocol_violation` close.
  internal func dispatch(_ message: TypedMessage) -> RappBridgeAction {
    switch side {
    case .proxy(var engine):
      let dispatched: ProxyDispatch
      do {
        dispatched = try engine.receive(message)
      } catch {
        side = .proxy(engine)
        return violationClose()
      }
      side = .proxy(engine)
      return action(for: dispatched)

    case .requester(var engine):
      let dispatched: RequesterDispatch
      do {
        dispatched = try engine.receive(message)
      } catch {
        side = .requester(engine)
        return violationClose()
      }
      side = .requester(engine)
      return action(for: dispatched)
    }
  }

  /// The caller's next step for one custodian dispatch.
  internal func action(for dispatch: ProxyDispatch) -> RappBridgeAction {
    switch dispatch {
    case .inspectPrerequisites(let operationIdentifier):
      operationAction(operationIdentifier, .inspectPrerequisites)

    case .awaitConsent(let operationIdentifier):
      operationAction(operationIdentifier, .awaitUserApproval)

    case .executeSafeRead(let operationIdentifier, let read):
      .custodianStep(operationIdentifier, .executeSafeRead, RappOperationDescriptor(read.operation))

    case .executeCardCommand(let operationIdentifier, let command):
      .custodianStep(
        operationIdentifier, .executeCardCommand, RappOperationDescriptor(command.operation))

    case .send(let message):
      send(message)

    case .notOperation:
      .noAction
    }
  }

  /// The caller's next step for one requester dispatch.
  internal func action(for dispatch: RequesterDispatch) -> RappBridgeAction {
    switch dispatch {
    case .cardStatus(let status):
      .cardStatus(status)

    case .progress(let operationIdentifier, let event):
      .progress(operationIdentifier, event)

    case .completed(let operationIdentifier, let result):
      .completed(operationIdentifier, RappOperationResult(result))

    case .ended(let operationIdentifier, _, let error),
      .refused(let operationIdentifier, let error):
      .terminal(operationIdentifier, RappTerminalReason(error))

    case .peerError, .ignored, .notOperation:
      .noAction
    }
  }

  /// A step naming the live operation the custodian is asked about.
  private func operationAction(
    _ operationIdentifier: RappOperationIdentifier, _ step: RappCustodianStep
  ) -> RappBridgeAction {
    guard case .proxy(let engine) = side, let request = engine.request(operationIdentifier) else {
      return .noAction
    }
    return .custodianStep(operationIdentifier, step, RappOperationDescriptor(request.operation))
  }

  /// Seals one typed message, or closes the session when the channel can no
  /// longer seal.
  internal func send(_ message: TypedMessage) -> RappBridgeAction {
    guard let messageType = message.messageType, let body = message.wireBody(),
      let frame = try? session.seal(messageType, body: body)
    else { return closingAction() }
    return .sendFrame(frame, operationId: message.referencedOperationIdentifier)
  }

  /// Seals one session-level message, or closes the session when the
  /// channel can no longer seal.
  internal func sendOrClose(
    _ messageType: MessageType, body: [String: WireValue]
  ) -> RappBridgeAction {
    guard let frame = try? session.seal(messageType, body: body) else { return closingAction() }
    return .sendFrame(frame, operationId: nil)
  }

  /// Ends the session without a notice of its own.
  internal func closingAction() -> RappBridgeAction {
    .sessionClosed(reason: nil, endedOperation: endOperations())
  }

  /// Ends the session and every operation of it (§8.1 item 3), naming the
  /// operation that ended with it.
  internal func endOperations() -> RappEndedOperation? {
    var ended: RappEndedOperation?
    switch side {
    case .proxy(var engine):
      switch engine.sessionClosed() {
      case .dropped(let operationIdentifier):
        ended = .dropped(operationIdentifier)

      case .continueCardExchange(let operationIdentifier):
        ended = .cardExchangeContinues(operationIdentifier)

      case nil:
        break
      }
      side = .proxy(engine)

    case .requester(var engine):
      ended = engine.sessionClosed().map(RappEndedOperation.dropped)
      side = .requester(engine)
    }
    liveness.close()
    closed = true
    session.close()
    return ended
  }

  /// Ends the session after an authenticated protocol violation: the sealed
  /// `protocol_violation` close, when the channel can still seal it, then
  /// the link drops.
  ///
  /// The pairing stays (§10.1).
  internal func violationClose() -> RappBridgeAction {
    let notice = try? session.seal(
      .sessionClose, body: ["reason": .text(CloseReasonName.protocolViolation)])
    let ended = endOperations()
    guard let notice else { return .sessionClosed(reason: nil, endedOperation: ended) }
    return .sendClose(notice, reason: .protocolViolation, endedOperation: ended)
  }

  internal func locked<Value>(_ body: () throws -> Value) rethrows -> Value {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}
