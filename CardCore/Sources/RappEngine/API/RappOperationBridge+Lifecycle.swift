// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension RappOperationBridge {
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
  public func beginSignDocument(  // swiftlint:disable:this function_parameter_count
    operationId: RappOperationIdentifier,
    documentName: String,
    keyProfile: RappCardKeyProfile,
    algorithm: RappSignatureAlgorithm,
    digest: Data,
    localStartMs: UInt64,
    expiresAfterMs: UInt64
  ) throws -> RappBridgeAction {
    try beginOperation(
      .signDocument(
        documentName: documentName, keyProfile: keyProfile.engineProfile,
        algorithm: algorithm.engineAlgorithm, digest: digest),
      operationId: operationId, localStartMs: localStartMs, expiresAfterMs: expiresAfterMs)
  }

  /// Begins signing documents under one PIN 2 entry (RAPP v26.10.21 §9.3);
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
  private func act(on envelope: Envelope, nowMs: UInt64) -> RappBridgeAction {
    switch envelope.messageType {
    case .livenessPing:
      guard let challenge = PingChallenge(body: envelope.body) else { return violationClose() }
      return sendOrClose(.livenessPong, body: ["challenge": .bytes(challenge.bytes)])

    case .livenessPong:
      guard let challenge = PingChallenge(body: envelope.body) else { return violationClose() }
      _ = liveness.receivePong(nowMilliseconds: nowMs, challenge: challenge)
      return .noAction

    case .sessionClose:
      var reason: RappCloseReason?
      if case .text(let name)? = envelope.body["reason"] {
        reason = RappCloseReason(rawValue: name)
      }
      return .sessionClosed(reason: reason, endedOperation: endOperations())

    case .pairingHello, .pairingConfirm, .pairingAbort, .pairingStored, .sessionReady:
      // A message of an earlier phase has no transition on an established
      // session.
      return violationClose()

    case .cardStatus, .error, .operationProgress, .operationRequest, .operationResult:
      let message: TypedMessage
      do {
        message = try SessionMessageCodec.message(from: envelope, nowMilliseconds: nowMs)
      } catch {
        return violationClose()
      }
      return dispatch(message)
    }
  }

  /// Advances liveness with the platform's monotonic time and fresh random
  /// challenge bytes: a ping after 5 seconds of silence, the session's end
  /// after 30 (§8.3).
  public func pollLiveness(nowMs: UInt64, challenge: Data) throws -> RappBridgeAction {
    guard let ping = PingChallenge(challenge) else { throw RappBindingError.InvalidInput }
    return locked {
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

  /// Closes the session; every operation of it is over and the pairing
  /// stays.
  public func closeSession() -> RappBridgeAction {
    locked { closingAction() }
  }

  /// Closes the session with an authenticated `session.close` carrying
  /// `reason`; the returned frame is delivered before the link drops.
  ///
  /// A session already closed gives `sessionClosed` without a frame.
  ///
  /// A custodian whose holder switched remote access off closes every open
  /// session with ``RappCloseReason/serviceWithdrawn`` before it stops
  /// accepting connections (§4.5).
  public func closeWithReason(_ reason: RappCloseReason) -> RappBridgeAction {
    locked {
      guard !closed else { return .sessionClosed(reason: nil, endedOperation: nil) }
      let notice = try? session.seal(.sessionClose, body: ["reason": .text(reason.rawValue)])
      let ended = endOperations()
      guard let notice else { return .sessionClosed(reason: nil, endedOperation: ended) }
      return .sendClose(notice, reason: reason, endedOperation: ended)
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
