// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension RappOperationBridge {
  /// The files a package holds, or nil for a single document.
  private static func package(holding names: [String]) throws -> ContainedFiles? {
    guard !names.isEmpty else { return nil }
    do {
      return try ContainedFiles(names: names)
    } catch {
      throw RappBindingError.InvalidInput
    }
  }

  /// Begins a card inspection.
  public func beginInspectCard(
    operationId: RappOperationIdentifier, localStartMs: UInt64, expiresAfterMs: UInt64
  ) throws -> RappBridgeAction {
    try beginOperation(
      .inspectCard, operationId: operationId, localStartMs: localStartMs,
      expiresAfterMs: expiresAfterMs)
  }

  /// Begins a cardholder identity read.
  public func beginReadIdentity(
    operationId: RappOperationIdentifier, localStartMs: UInt64, expiresAfterMs: UInt64
  ) throws -> RappBridgeAction {
    try beginOperation(
      .readIdentity, operationId: operationId, localStartMs: localStartMs,
      expiresAfterMs: expiresAfterMs)
  }

  /// Begins a certificate read, owned by the profile whose key it serves.
  public func beginReadCertificate(
    operationId: RappOperationIdentifier,
    signatureCertificate: Bool,
    localStartMs: UInt64,
    expiresAfterMs: UInt64
  ) throws -> RappBridgeAction {
    try beginOperation(
      .readCertificate(kind: signatureCertificate ? .signature : .authentication),
      operationId: operationId, localStartMs: localStartMs, expiresAfterMs: expiresAfterMs)
  }

  /// Begins a browser authentication over an already-hashed challenge.
  public func beginBrowserAuthentication(  // swiftlint:disable:this function_parameter_count
    operationId: RappOperationIdentifier,
    origin: String,
    keyProfile: RappCardKeyProfile,
    algorithm: RappSignatureAlgorithm,
    digest: Data,
    localStartMs: UInt64,
    expiresAfterMs: UInt64
  ) throws -> RappBridgeAction {
    try beginOperation(
      .browserAuthenticate(
        origin: origin, keyProfile: keyProfile.engineProfile,
        algorithm: algorithm.engineAlgorithm, digest: digest),
      operationId: operationId, localStartMs: localStartMs, expiresAfterMs: expiresAfterMs)
  }

  /// Begins a document signature over a document digest.
  ///
  /// For a package, `documentName` is the package's own name and
  /// `containedFiles` the names of the files it holds, in container order;
  /// empty for a single document (RAPP v26.11.2 §9.3).
  ///
  /// - Throws: ``RappBindingError/InvalidInput`` for invalid names or a
  ///   package whose request does not fit one frame.
  public func beginSignDocument(  // swiftlint:disable:this function_parameter_count
    operationId: RappOperationIdentifier,
    documentName: String,
    containedFiles: [String],
    keyProfile: RappCardKeyProfile,
    algorithm: RappSignatureAlgorithm,
    digest: Data,
    localStartMs: UInt64,
    expiresAfterMs: UInt64
  ) throws -> RappBridgeAction {
    try beginOperation(
      .signDocument(
        document: DocumentToSign(
          name: documentName, containedFiles: try Self.package(holding: containedFiles)),
        keyProfile: keyProfile.engineProfile,
        algorithm: algorithm.engineAlgorithm, digest: digest),
      operationId: operationId, localStartMs: localStartMs, expiresAfterMs: expiresAfterMs)
  }

  /// Begins signing documents under one PIN 2 entry (RAPP v26.11.2 §9.3);
  /// names and digests pair up by position.
  public func beginBatchSignDocuments(  // swiftlint:disable:this function_parameter_count
    operationId: RappOperationIdentifier,
    documentNames: [String],
    keyProfile: RappCardKeyProfile,
    algorithm: RappSignatureAlgorithm,
    digests: [Data],
    localStartMs: UInt64,
    expiresAfterMs: UInt64
  ) throws -> RappBridgeAction {
    try beginOperation(
      .batchSignDocuments(
        documentNames: documentNames, keyProfile: keyProfile.engineProfile,
        algorithm: algorithm.engineAlgorithm, digests: digests),
      operationId: operationId, localStartMs: localStartMs, expiresAfterMs: expiresAfterMs)
  }

  /// Decrypts, authenticates, schema-checks, and dispatches one sealed frame
  /// from the peer.
  ///
  /// A frame that fails authenticated decryption ends the session; one that
  /// decrypted and broke the protocol ends it with a sealed
  /// `protocol_violation` close. Neither touches the pairing (§10.1).
  public func receiveFrame(bytes: Data, nowMs: UInt64) -> RappBridgeAction {
    locked {
      if let sent = awaitingEcho { return receiveWhileAwaitingEcho(bytes, sent: sent) }
      guard !closed else { return .noAction }
      let envelope: Envelope
      do {
        envelope = try session.open(bytes)
      } catch SessionError.unexpectedMessage {
        return violationClose()
      } catch {
        return closingAction()
      }
      liveness.heard(nowMilliseconds: nowMs)
      return act(on: envelope, nowMs: nowMs)
    }
  }

  /// The step for one authenticated message on the established session;
  /// called with the lock held.
  ///
  /// A custodian admits nothing before the requester's `session.hello` but
  /// a close (§7.1 item 6).
  private func act(on envelope: Envelope, nowMs: UInt64) -> RappBridgeAction {
    if !helloReceived, envelope.messageType != .sessionHello,
      envelope.messageType != .sessionClose
    {
      return violationClose()
    }
    switch envelope.messageType {
    case .livenessPing, .livenessPong:
      return liveness(envelope, nowMs: nowMs)

    case .sessionClose, .sessionHello:
      return sessionMessage(envelope)

    case .pairingHello, .pairingConfirm, .pairingAbort, .pairingStored, .sessionReady:
      // A message of an earlier phase has no transition on an established
      // session.
      return violationClose()

    case .cardStatus, .error, .operationProgress, .operationRequest, .operationResult:
      let message: TypedMessage
      do {
        message = try SessionMessageCodec.message(from: envelope, nowMilliseconds: nowMs)
      } catch {
        RappRefusalLog.refused(envelope.messageType, because: error)
        return violationClose()
      }
      return dispatch(message)
    }
  }

  /// A ping is answered at once; a pong settles the outstanding challenge.
  private func liveness(_ envelope: Envelope, nowMs: UInt64) -> RappBridgeAction {
    guard let challenge = PingChallenge(body: envelope.body) else { return violationClose() }
    guard envelope.messageType == .livenessPing else {
      _ = liveness.receivePong(nowMilliseconds: nowMs, challenge: challenge)
      return .noAction
    }
    return sendOrClose(.livenessPong, body: ["challenge": .bytes(challenge.bytes)])
  }

  /// The peer's close, answered with its echo (§7.1 item 7), or the
  /// requester's hello, which a custodian takes once (§7.1 item 6).
  private func sessionMessage(_ envelope: Envelope) -> RappBridgeAction {
    if envelope.messageType == .sessionClose {
      guard case .text(let name)? = envelope.body["reason"],
        let reason = RappCloseReason(rawValue: name)
      else { return violationClose() }
      return echoClose(reason)
    }
    guard case .proxy = side, !helloReceived,
      let hello = try? SessionHello.from(body: envelope.body)
    else { return violationClose() }
    helloReceived = true
    return .peerNamed(hello.displayName)
  }

  /// Advances liveness with the platform's monotonic time and fresh random
  /// challenge bytes: a ping after 5 seconds of silence, the session's end
  /// after 30 (§8.3).
  public func pollLiveness(nowMs: UInt64, challenge: Data) throws -> RappBridgeAction {
    guard let ping = PingChallenge(challenge) else { throw RappBindingError.InvalidInput }
    return locked {
      guard awaitingEcho == nil else { return .noAction }
      guard !closed else { return .sessionClosed(reason: nil, endedOperation: nil) }
      switch liveness.poll(nowMilliseconds: nowMs, nextChallenge: ping) {
      case .noAction:
        return .noAction

      case .sendPing(let outstanding):
        return sendOrClose(.livenessPing, body: ["challenge": .bytes(outstanding.bytes)])

      case .closeSession, .alreadyClosed:
        return closingAction()
      }
    }
  }

  /// Closes the session; every operation of it is over and the pairing stays.
  ///
  /// It also ends the wait for the echo of this endpoint's close.
  public func closeSession() -> RappBridgeAction {
    locked {
      if awaitingEcho != nil {
        awaitingEcho = nil
        session.close()
        return .sessionClosed(reason: nil, endedOperation: nil)
      }
      return closingAction()
    }
  }

  /// Closes the session with an authenticated `session.close` carrying
  /// `reason`; the returned frame is delivered, then the endpoint waits for
  /// the peer's echo within its bound before the link drops (§7.1 item 7).
  ///
  /// A session already closed, or already waiting for an echo, gives
  /// `sessionClosed` or nothing, without a frame.
  ///
  /// An endpoint that withdraws, custodian or requester, closes every open
  /// session with ``RappCloseReason/serviceWithdrawn`` (§4.5 items 3 and 8)
  /// and waits at most ``rappQuitWithdrawalBoundMs()`` for each echo.
  public func closeWithReason(_ reason: RappCloseReason) -> RappBridgeAction {
    locked {
      guard awaitingEcho == nil else { return .noAction }
      guard !closed else { return .sessionClosed(reason: nil, endedOperation: nil) }
      return sealClose(reason)
    }
  }

  /// Starts one operation on the requester side and releases its request.
  private func beginOperation(
    _ operation: CardOperation,
    operationId: RappOperationIdentifier,
    localStartMs: UInt64,
    expiresAfterMs: UInt64
  ) throws -> RappBridgeAction {
    try locked {
      guard case .requester(var engine) = side, !closed else { throw RappBindingError.WrongPhase }
      guard grantedProfiles.contains(operation.requiredProfile) else {
        throw RappBindingError.InvalidInput
      }
      let message: TypedMessage
      do {
        let request = try OperationRequest(
          operationIdentifier: operationId,
          profile: operation.requiredProfile,
          localStartMilliseconds: localStartMs,
          expiresAfterMilliseconds: expiresAfterMs,
          operation: operation)
        message = try engine.begin(request)
      } catch EngineError.liveOperation {
        throw RappBindingError.WrongPhase
      } catch {
        throw RappBindingError.InvalidInput
      }
      side = .requester(engine)
      return send(message)
    }
  }
}
