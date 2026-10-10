// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension RappOperationBridge {
  /// Runs the requester side over an established session.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` when the session is not
  ///   established, and ``RappBindingError/LocalStateFailure`` when stored
  ///   records could not be recovered.
  public static func beginRequester(
    session: RappSessionBridge,
    vault: RappOperationVault,
    maximumLifetimeMs: UInt64,
    liveness: RappLivenessConfiguration,
    nowMs: UInt64
  ) throws -> RappOperationBridge {
    let established = try session.takeEstablished()
    let recovered = try recoveredRequesterRecords(
      vault: vault, pairIdentifier: established.pair.pairIdentifier)
    return try RappOperationBridge(
      vault: vault,
      pairIdentifier: established.pair.pairIdentifier,
      session: established.session,
      side: .requester(RequesterOperationEngine(recovered: recovered)),
      maximumLifetimeMs: maximumLifetimeMs,
      liveness: liveness,
      nowMilliseconds: nowMs)
  }

  /// Runs the proxy side over an established session.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` when the session is not
  ///   established, and ``RappBindingError/LocalStateFailure`` when stored
  ///   records could not be recovered.
  public static func beginProxy(
    session: RappSessionBridge,
    vault: RappOperationVault,
    maximumLifetimeMs: UInt64,
    liveness: RappLivenessConfiguration,
    nowMs: UInt64
  ) throws -> RappOperationBridge {
    let established = try session.takeEstablished()
    let recovered = try recoveredProxyRecords(
      vault: vault, pairIdentifier: established.pair.pairIdentifier)
    return try RappOperationBridge(
      vault: vault,
      pairIdentifier: established.pair.pairIdentifier,
      session: established.session,
      side: .proxy(
        ProxyOperationEngine(
          grantedProfiles: established.pair.profiles, recovered: recovered)),
      maximumLifetimeMs: maximumLifetimeMs,
      liveness: liveness,
      nowMilliseconds: nowMs)
  }

  /// Whether a failure result's pairing effect is revocation, per the
  /// specification's failure taxonomy.
  internal static func failureRevokesPairing(_ message: TypedMessage) -> Bool {
    guard case .operationResult(let result) = message else { return false }
    return result.status == .credentialRejected
  }

  /// Names an engine failure in the public vocabulary.
  internal static func bindingError(_ error: EngineError) -> RappBindingError {
    switch error {
    case .authenticatedProtocolViolation:
      .ProtocolFailure

    case .unknownLocalOperation, .duplicateLocalOperationIdentifier, .invalidLocalValue:
      .InvalidInput

    default:
      .WrongPhase
    }
  }

  /// Begins a card and retry-state inspection.
  public func beginInspectCard(
    operationId: Data, localStartMs: UInt64, expiresAfterMs: UInt64
  ) throws -> RappBridgeAction {
    try beginOperation(
      .inspectCard, operationId: operationId, localStartMs: localStartMs,
      expiresAfterMs: expiresAfterMs)
  }

  /// Begins a cardholder identity read.
  public func beginReadIdentity(
    operationId: Data, localStartMs: UInt64, expiresAfterMs: UInt64
  ) throws -> RappBridgeAction {
    try beginOperation(
      .readIdentity, operationId: operationId, localStartMs: localStartMs,
      expiresAfterMs: expiresAfterMs)
  }

  /// Begins a certificate read, owned by the profile whose key it serves.
  public func beginReadCertificate(
    operationId: Data, signatureCertificate: Bool, localStartMs: UInt64, expiresAfterMs: UInt64
  ) throws -> RappBridgeAction {
    try beginOperation(
      .readCertificate(kind: signatureCertificate ? .signature : .authentication),
      operationId: operationId, localStartMs: localStartMs, expiresAfterMs: expiresAfterMs)
  }

  /// Begins a browser authentication over an already-hashed challenge.
  public func beginBrowserAuthentication(  // swiftlint:disable:this function_parameter_count
    operationId: Data,
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
    operationId: Data,
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

  /// Begins signing 1 to 64 documents under one PIN 2 entry (RAPP v26.10.9
  /// §9.3); names and digests pair up by position.
  public func beginBatchSignDocuments(  // swiftlint:disable:this function_parameter_count
    operationId: Data,
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

  /// Consumes one sealed frame from the peer.
  ///
  /// The unexpected-input policy (specification section 14.5) decides the
  /// blast radius here: a frame that fails authenticated decryption closes
  /// only the session, while a frame that decrypted and then broke the
  /// protocol is attributable to the peer holding the pair keys and
  /// revokes the pairing (section 14.6).
  ///
  /// - Throws: ``RappBindingError/ProtocolFailure`` when the authenticated
  ///   peer sent something the protocol forbids outside the modelled
  ///   violation handling.
  public func receiveFrame(bytes: Data, nowMs: UInt64) throws -> RappBridgeAction {
    try locked {
      guard !closed else { return RappBridgeAction(kind: .noAction) }
      let envelope: Envelope
      do {
        envelope = try session.open(bytes)
      } catch SessionError.integrityFailure {
        // Failed authenticated decryption is network-attributable and
        // has no pairing effect.
        return closingAction(.sessionClosed)
      } catch SessionError.unexpectedMessage {
        // The frame decrypted, so it came from the paired peer holding
        // the right key, and its contents broke the protocol.
        return violationClose()
      } catch {
        return closingAction(.sessionClosed)
      }
      if let livenessAction = try livenessReply(to: envelope, nowMs: nowMs) {
        return livenessAction
      }
      let message: TypedMessage
      do {
        message = try SessionMessageCodec.message(
          from: envelope,
          pairIdentifier: pairIdentifier,
          sessionIdentifier: session.sessionIdentifier,
          nowMilliseconds: nowMs)
      } catch {
        // An authenticated body that does not parse is a schema
        // violation from the peer holding the pair keys.
        return violationClose()
      }
      if case .other = message {
        // A pairing-phase or readiness message on an established
        // session has no legal transition and is attributable.
        return violationClose()
      }
      return try dispatch(message, nowMs: nowMs)
    }
  }

  /// Probes the peer, or reports that the deadline has passed.
  public func pollLiveness(
    nowMs: UInt64, challenge: Data, jitterMs: Int64
  ) throws -> RappBridgeAction {
    try locked {
      guard !closed else { return RappBridgeAction(kind: .noAction) }
      guard let ping = PingChallenge(challenge) else { throw RappBindingError.InvalidInput }
      switch liveness.poll(
        nowMilliseconds: nowMs, nextChallenge: ping, jitterMilliseconds: jitterMs)
      {
      case .sendPing(let outstanding):
        let frame = try sealed(.livenessPing, body: livenessBody(outstanding.bytes))
        return RappBridgeAction(kind: .sendFrame, frame: frame)

      case .probeMissed(let nextProbeAtMilliseconds):
        return RappBridgeAction(kind: .noAction, nextPollAtMs: nextProbeAtMilliseconds)

      case .noAction:
        return RappBridgeAction(kind: .noAction)

      case .closeSession, .alreadyClosed:
        return closingAction(.sessionClosed)
      }
    }
  }

  /// The body both liveness messages carry.
  ///
  /// A ping is not only a probe: it also reports how far this side has read,
  /// and the schema requires that report. Building the body in one place
  /// keeps the ping and the pong from drifting apart from the schema, which
  /// is what a peer would otherwise read as a wire violation.
  internal func livenessBody(_ challenge: Data) -> [String: WireValue] {
    [
      "challenge": .bytes(challenge),
      "last_received_sequence": .unsigned(session.lastReceivedSequence),
    ]
  }

  /// Closes the session and classifies every operation still in flight.
  public func closeSession() -> RappBridgeAction {
    locked {
      guard !closed else { return RappBridgeAction(kind: .noAction) }
      return closingAction(.sessionClosed)
    }
  }

  /// Starts one operation on the requester side and releases its request.
  internal func beginOperation(
    _ operation: CardOperation,
    operationId: Data,
    localStartMs: UInt64,
    expiresAfterMs: UInt64
  ) throws -> RappBridgeAction {
    try locked {
      guard case .requester(var engine) = side else { throw RappBindingError.WrongPhase }
      defer { side = .requester(engine) }
      var store = VaultRequesterJournalStore(vault: vault, pairIdentifier: pairIdentifier)
      let message = try mapping { () -> TypedMessage in
        let request = try OperationRequest(
          operationIdentifier: operationId,
          pairIdentifier: pairIdentifier,
          sessionIdentifier: session.sessionIdentifier,
          profile: operation.requiredProfile,
          localStartMilliseconds: localStartMs,
          expiresAfterMilliseconds: expiresAfterMs,
          operation: operation)
        return try engine.begin(request, store: &store)
      }
      let frame = try sealedMessage(message)
      return RappBridgeAction(kind: .sendFrame, operationId: operationId, frame: frame)
    }
  }

  /// Runs one proxy step that produces a dispatch, writing the engine back.
  internal func withProxy(
    _ body: (inout ProxyOperationEngine, inout VaultProxyJournalStore) throws -> ProxyDispatch
  ) throws -> RappBridgeAction {
    try locked {
      guard case .proxy(var engine) = side else { throw RappBindingError.WrongPhase }
      defer { side = .proxy(engine) }
      var store = VaultProxyJournalStore(vault: vault, pairIdentifier: pairIdentifier)
      let dispatch = try mapping { try body(&engine, &store) }
      return try action(for: dispatch)
    }
  }

  /// Records a stable failure and releases it.
  internal func finishFailure(
    operationId: Data, failure: ProxyFailure
  ) throws -> RappBridgeAction {
    try withProxy { engine, store in
      try engine.finishFailure(operationIdentifier: operationId, failure: failure, store: &store)
    }
  }

  /// Retains a completed answer before it may be released.
  internal func complete(
    operationId: Data, result: CardOperationResult
  ) throws -> RappBridgeAction {
    try withProxy { engine, store in
      guard let reference = engine.reference(operationId) else {
        #if DEBUG
          EngineTrace.say(
            "no live operation for this answer: live "
              + "\(engine.operations.count), stages "
              + "\(engine.operations.map { String(describing: $0.stage) })")
        #endif
        throw RappBindingError.WrongPhase
      }
      #if DEBUG
        let stage =
          engine.operations
          .first { $0.reference == reference }
          .map { String(describing: $0.stage) } ?? "none"
        EngineTrace.say("answering a transaction in stage \(stage)")
      #endif
      return try engine.finishCompleted(
        operationIdentifier: operationId,
        result: OperationResultMessage.completed(reference: reference, result: result),
        store: &store)
    }
  }
}
