// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Turning an engine dispatch into the caller's next step.
extension RappOperationBridge {
  /// Classifies one authenticated message on whichever side runs here.
  ///
  /// A message the engine refuses as an authenticated protocol violation
  /// takes the specification's first-incident revocation rather than
  /// escaping as an error the caller cannot classify.
  internal func dispatch(_ message: TypedMessage, nowMs: UInt64) throws -> RappBridgeAction {
    switch side {
    case .proxy(var engine):
      return try dispatchProxy(&engine, message: message, nowMs: nowMs)
    case .requester(var engine):
      return try dispatchRequester(&engine, message: message, nowMs: nowMs)
    }
  }

  /// Runs one proxy-side receive and stores the engine's new state first.
  private func dispatchProxy(
    _ engine: inout ProxyOperationEngine,
    message: TypedMessage,
    nowMs: UInt64
  ) throws -> RappBridgeAction {
    var store = VaultProxyJournalStore(vault: vault, pairIdentifier: pairIdentifier)
    let dispatch: ProxyDispatch
    do {
      dispatch = try mapping {
        try engine.receive(
          message, store: &store, nowMilliseconds: nowMs,
          maximumLifetimeMilliseconds: maximumLifetimeMilliseconds)
      }
    } catch let error as RappBindingError where error == .ProtocolFailure {
      side = .proxy(engine)
      return violationClose()
    } catch {
      side = .proxy(engine)
      throw error
    }
    side = .proxy(engine)
    return try action(for: dispatch)
  }

  /// Runs one requester-side receive and stores the engine's new state first.
  private func dispatchRequester(
    _ engine: inout RequesterOperationEngine,
    message: TypedMessage,
    nowMs _: UInt64
  ) throws -> RappBridgeAction {
    var store = VaultRequesterJournalStore(vault: vault, pairIdentifier: pairIdentifier)
    let dispatch: RequesterDispatch
    do {
      dispatch = try mapping { try engine.receive(message, store: &store) }
    } catch let error as RappBindingError where error == .ProtocolFailure {
      side = .requester(engine)
      return violationClose()
    } catch {
      side = .requester(engine)
      throw error
    }
    side = .requester(engine)
    return try action(for: dispatch)
  }

  /// Answers a liveness ping, or records a pong, before the operation layer
  /// sees the envelope.
  internal func livenessReply(to envelope: Envelope, nowMs: UInt64) throws -> RappBridgeAction? {
    switch envelope.messageType {
    case .livenessPing:
      var body = envelope.body
      let challenge = try takeBytes(&body, "challenge")
      let frame = try sealed(.livenessPong, body: livenessBody(challenge))
      return RappBridgeAction(kind: .sendFrame, frame: frame)

    case .livenessPong:
      var body = envelope.body
      let echo = try takeBytes(&body, "challenge")
      guard let challenge = PingChallenge(echo) else { return RappBridgeAction(kind: .noAction) }
      _ = liveness.receivePong(nowMilliseconds: nowMs, challenge: challenge)
      return RappBridgeAction(kind: .noAction)

    case .sessionClose:
      // A peer that entered revoked says so over the authenticated
      // channel; receiving that notice marks this side's pairing revoked
      // too (specification section 14.6). Every other reason closes only
      // the session.
      if case .text(let reason)? = envelope.body["reason"],
        CloseReasonName.revokesPairing(reason)
      {
        var action = closingAction(.pairRevoked)
        action.revokesPairing = true
        return action
      }
      return closingAction(.sessionClosed)

    default:
      return nil
    }
  }

  /// Releases one failure result, closing the session when it is the last
  /// frame the session carries.
  private func sendFailureAction(
    message: TypedMessage, closeSession: Bool
  ) throws -> RappBridgeAction {
    let frame = try sealedMessage(message)
    let revokes = Self.failureRevokesPairing(message)
    if closeSession {
      // The failure result is the last frame this session carries; no
      // later inbound frame may admit new work (invariant INV-16), and
      // whatever else is still in flight is classified now.
      classifyLiveOperations()
      closed = true
      session.close()
    }
    return RappBridgeAction(
      kind: .sendFrame,
      operationId: message.referencedOperationIdentifier,
      frame: frame,
      closeSessionAfterSend: closeSession,
      revokesPairing: revokes)
  }

  /// Releases one outbound message on the authenticated session.
  private func sendAction(message: TypedMessage) throws -> RappBridgeAction {
    RappBridgeAction(
      kind: .sendFrame,
      operationId: message.referencedOperationIdentifier,
      frame: try sealedMessage(message))
  }

  /// One session-level frame action, or nil for operation steps.
  private func sessionFrameAction(for dispatch: ProxyDispatch) throws -> RappBridgeAction? {
    switch dispatch {
    case .send(let message):
      return try sendAction(message: message)

    case .sendFailure(let message, let closeSession):
      return try sendFailureAction(message: message, closeSession: closeSession)

    case .ignoredStale(let operationIdentifier, let response):
      return try staleAction(operationIdentifier: operationIdentifier, response: response)

    case .notOperation:
      return RappBridgeAction(kind: .noAction)

    default:
      return nil
    }
  }

  /// The caller's next step for one proxy dispatch.
  internal func action(for dispatch: ProxyDispatch) throws -> RappBridgeAction {
    if let frame = try sessionFrameAction(for: dispatch) { return frame }
    switch dispatch {

    case .inspectPrerequisites(let operationIdentifier):
      return try operationAction(.inspectPrerequisites, operationIdentifier: operationIdentifier)

    case .executeSafeRead(let operationIdentifier, _):
      return try operationAction(.executeSafeRead, operationIdentifier: operationIdentifier)

    case .beginCardCommand(let operationIdentifier):
      return try operationAction(.executeCardCommand, operationIdentifier: operationIdentifier)

    case .advisoryCancellation(let operationIdentifier):
      return RappBridgeAction(kind: .advisoryCancellation, operationId: operationIdentifier)

    case .cancelled(let operationIdentifier):
      return RappBridgeAction(
        kind: .cancelled, operationId: operationIdentifier,
        terminalState: OperationState.cancelled.rawValue,
        terminalReason: .cancelled)

    case .resultAcknowledged(let operationIdentifier):
      return RappBridgeAction(kind: .resultAcknowledged, operationId: operationIdentifier)

    case .ignoredDuplicateCommit(let operationIdentifier):
      return RappBridgeAction(kind: .ignoredDuplicate, operationId: operationIdentifier)

    default:
      throw RappBindingError.WrongPhase
    }
  }

  /// Answers one stale reference and changes nothing.
  private func staleAction(
    operationIdentifier: Data, response: TypedMessage
  ) throws -> RappBridgeAction {
    RappBridgeAction(
      kind: .sendFrame, operationId: operationIdentifier,
      frame: try sealedMessage(response))
  }

  /// Commits one prepared operation and releases its first frame.
  private func preparedAction(
    operationIdentifier: Data
  ) throws -> RappBridgeAction {
    guard case .requester(var engine) = side else { throw RappBindingError.WrongPhase }
    defer { side = .requester(engine) }
    var store = VaultRequesterJournalStore(vault: vault, pairIdentifier: pairIdentifier)
    let message = try mapping {
      try engine.commit(operationIdentifier: operationIdentifier, store: &store)
    }
    return RappBridgeAction(
      kind: .sendFrame, operationId: operationIdentifier,
      frame: try sealedMessage(message))
  }

  /// The caller's next step for one requester dispatch.
  internal func action(for dispatch: RequesterDispatch) throws -> RappBridgeAction {
    if let action = try sessionAction(for: dispatch) { return action }
    switch dispatch {
    case .prepared(let operationIdentifier):
      return try preparedAction(operationIdentifier: operationIdentifier)

    case .progress(let operationIdentifier, let event):
      return RappBridgeAction(
        kind: .progress,
        operationId: operationIdentifier,
        progressEvent: event)

    case .sendResultAcknowledgement(let operationIdentifier, let message):
      return RappBridgeAction(
        kind: .resultAcknowledgment, operationId: operationIdentifier,
        frame: try sealedMessage(message))

    case .terminal(let operationIdentifier, let state, let reason):
      // A credential-rejected result revokes the pairing on both peers
      // (specification failure taxonomy); this is the requester learning.
      return RappBridgeAction(
        kind: .terminal, operationId: operationIdentifier, terminalState: state.rawValue,
        terminalReason: RappTerminalReason(reason),
        revokesPairing: reason == .credentialRejected)

    case .cancellationReceived(let operationIdentifier, let state):
      // Past the commit the peer's cancel is advisory: the operation is
      // still live and its card-determined result is still to come.
      guard state.isTerminal else {
        return RappBridgeAction(kind: .advisoryCancellation, operationId: operationIdentifier)
      }
      return RappBridgeAction(
        kind: .cancelled, operationId: operationIdentifier, terminalState: state.rawValue,
        terminalReason: .cancelled)

    default:
      throw RappBindingError.WrongPhase
    }
  }

  private func sessionAction(for dispatch: RequesterDispatch) throws -> RappBridgeAction? {
    switch dispatch {
    case .peerBusy:
      RappBridgeAction(kind: .peerBusy)

    case .peerUnknownOperation(let operationIdentifier):
      RappBridgeAction(kind: .peerUnknownOperation, operationId: operationIdentifier)

    case .statusAnnotated(let operationIdentifier):
      RappBridgeAction(kind: .noAction, operationId: operationIdentifier)

    case .ignoredStale(let operationIdentifier, let response):
      try staleAction(operationIdentifier: operationIdentifier, response: response)

    case .notOperation:
      RappBridgeAction(kind: .noAction)

    default:
      nil
    }
  }

  /// A step naming the operation the holder is being asked about.
  internal func operationAction(
    _ kind: RappBridgeActionKind, operationIdentifier: Data
  ) throws -> RappBridgeAction {
    guard case .proxy(let engine) = side, let operation = engine.operation(operationIdentifier)
    else { throw RappBindingError.WrongPhase }
    return RappBridgeAction(
      kind: kind,
      operationId: operationIdentifier,
      operation: RappOperationDescriptor(operation))
  }

  /// Marks the bridge spent and names why.
  ///
  /// Every close classifies the operations still in flight, so a session
  /// ended by the peer or by an integrity failure leaves the same durable
  /// terminal records a locally requested close does.
  internal func closingAction(_ kind: RappBridgeActionKind) -> RappBridgeAction {
    classifyLiveOperations()
    closed = true
    session.close()
    return RappBridgeAction(kind: kind)
  }

  /// Classifies every live operation for a closing session.
  ///
  /// Best effort by construction: a record whose terminal write fails
  /// stays at its last persisted state, which recovery terminalizes the
  /// next time the pairing begins operations.
  internal func classifyLiveOperations() {
    switch side {
    case .proxy(var engine):
      var store = VaultProxyJournalStore(vault: vault, pairIdentifier: pairIdentifier)
      _ = engine.sessionClosed(store: &store)
      side = .proxy(engine)

    case .requester(var engine):
      var store = VaultRequesterJournalStore(vault: vault, pairIdentifier: pairIdentifier)
      _ = engine.sessionClosed(store: &store)
      side = .requester(engine)
    }
  }

  /// Ends the session because the proxy can no longer serve the card.
  ///
  /// The pairing stays. Households keep the same peers while cards come
  /// and go; only the published identity leaves with the card.
  public func cardUnavailableClose() -> RappBridgeAction {
    locked {
      guard !closed else { return RappBridgeAction(kind: .noAction) }
      classifyLiveOperations()
      let notice = try? session.seal(
        .sessionClose,
        body: [
          "reason": .text(CloseReasonName.cardUnavailable),
          "last_received_sequence": .unsigned(session.lastReceivedSequence),
        ])
      closed = true
      session.close()
      return RappBridgeAction(
        kind: .sessionClosed,
        frame: notice,
        closeSessionAfterSend: notice != nil)
    }
  }

  /// Ends the session and the pairing after an authenticated protocol
  /// violation, per the specification's first-incident revocation.
  ///
  /// The best-effort close notice is sealed while the channel still
  /// exists; the caller releases it and durably revokes the pairing.
  internal func violationClose() -> RappBridgeAction {
    classifyLiveOperations()
    let notice = try? session.seal(
      .sessionClose,
      body: [
        "reason": .text(CloseReasonName.protocolViolation),
        "last_received_sequence": .unsigned(session.lastReceivedSequence),
      ])
    closed = true
    session.close()
    return RappBridgeAction(
      kind: .pairRevoked,
      frame: notice,
      closeSessionAfterSend: notice != nil,
      revokesPairing: true)
  }

  internal func sealedMessage(_ message: TypedMessage) throws -> Data {
    try mapping { try SessionMessageCodec.frame(for: message, session: &session) }
  }

  internal func sealed(_ messageType: MessageType, body: [String: WireValue]) throws -> Data {
    try mapping { try session.seal(messageType, body: body) }
  }

  internal func locked<Value>(_ body: () throws -> Value) rethrows -> Value {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  /// Runs an engine step, naming its failure in the public vocabulary.
  internal func mapping<Value>(_ body: () throws -> Value) throws -> Value {
    do {
      return try body()
    } catch let error as RappBindingError {
      throw error
    } catch let error as EngineError {
      throw Self.bindingError(error)
    } catch is AuthorizationError, is CardOperationError, is JournalError {
      throw RappBindingError.WrongPhase
    } catch is SessionError {
      throw RappBindingError.ProtocolFailure
    } catch {
      throw RappBindingError.LocalStateFailure
    }
  }
}
