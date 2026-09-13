// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// An established session: its channel, its sequence window, its liveness
/// timer, and the state the tables advance.
///
/// The runtime holds the pieces together and classifies what arrives. It
/// never invents an action list: a security event is applied to `RappState`,
/// which resolves the component rules, and the resulting actions are handed
/// back untouched.
internal struct EndpointRuntime {
  /// The body field naming the challenge a ping carries and a pong echoes.
  private static let challengeField = "challenge"

  /// The body field carrying the highest sequence accepted so far.
  private static let lastReceivedSequenceField = "last_received_sequence"

  /// The sequence reported before any peer message has been accepted.
  private static let noSequenceAccepted: UInt64 = 0

  private let sessionIdentifier: Data

  private var channel: RappSecureChannel?

  private var sequenceGuard: SequenceGuard

  private var liveness: LivenessTracker

  private var state: RappState

  /// The endpoint's current projection of the three machines.
  internal var currentState: RappState { state }

  /// Whether the secure channel is still open.
  internal var isOpen: Bool { channel != nil }

  /// The highest peer sequence accepted so far, for liveness bodies.
  internal var lastReceivedSequence: UInt64 {
    sequenceGuard.lastReceivedSequence ?? Self.noSequenceAccepted
  }

  internal init(
    sessionIdentifier: Data,
    channel: RappSecureChannel,
    state: RappState,
    liveness: LivenessTracker
  ) {
    self.sessionIdentifier = sessionIdentifier
    self.channel = channel
    self.state = state
    self.liveness = liveness
    sequenceGuard = SequenceGuard(sessionIdentifier: sessionIdentifier)
  }

  /// Encrypts one message and allocates its sequence.
  internal mutating func send(
    messageType: MessageType,
    body: [String: WireValue]
  ) throws -> BinaryFrame {
    guard var live = channel else { throw RuntimeSendError.sessionClosed }
    do {
      let sequence = try sequenceGuard.nextOutgoing()
      let envelope = Envelope(
        messageType: messageType,
        sessionIdentifier: sessionIdentifier,
        sequence: sequence,
        body: body,
        critical: [],
        extensions: [:])
      let sealed = try live.seal(try envelope.encoded())
      channel = live
      return try BinaryFrame(reconstructing: sealed)
    } catch let error as WireError {
      channel = live
      throw RuntimeSendError.encoding(error)
    } catch {
      channel = live
      throw error
    }
  }

  /// Opens one frame, classifies it, and advances the machines.
  internal mutating func receive(
    _ frame: BinaryFrame,
    nowMilliseconds: UInt64
  ) -> RuntimeReceive {
    guard var live = channel else { return .discarded(.trafficAfterClosed) }

    let plaintext: Data
    do {
      plaintext = try live.open(frame.bytes)
      channel = live
    } catch {
      channel = live
      return integrityFailed()
    }

    guard let envelope = try? Envelope.decode(plaintext) else {
      return violated()
    }
    do {
      try sequenceGuard.acceptIncoming(
        sessionIdentifier: envelope.sessionIdentifier, sequence: envelope.sequence)
    } catch {
      return violated()
    }
    return dispatch(envelope, nowMilliseconds: nowMilliseconds)
  }

  /// Advances the liveness policy against an injected monotonic timestamp.
  internal mutating func poll(
    nowMilliseconds: UInt64,
    nextChallenge: PingChallenge,
    jitterMilliseconds: Int64
  ) -> RuntimePoll {
    switch liveness.poll(
      nowMilliseconds: nowMilliseconds,
      nextChallenge: nextChallenge,
      jitterMilliseconds: jitterMilliseconds)
    {
    case .noAction:
      return .noAction

    case .sendPing(let challenge):
      guard let frame = try? send(messageType: .livenessPing, body: livenessBody(challenge))
      else { return .alreadyClosed }
      return .send(frame)

    case .probeMissed(let nextProbeAt):
      return .checking(
        nextProbeAtMilliseconds: nextProbeAt, outcome: state.livenessMissed())

    case .closeSession:
      let outcome = state.sessionIntegrityFailed()
      channel = nil
      return .sessionClosed(outcome)

    case .alreadyClosed:
      return .alreadyClosed
    }
  }

  /// Closes the session locally without ending the pairing.
  internal mutating func closeSession() {
    liveness.close()
    channel = nil
  }

  private mutating func dispatch(
    _ envelope: Envelope,
    nowMilliseconds: UInt64
  ) -> RuntimeReceive {
    switch envelope.messageType {
    case .livenessPing:
      guard case .bytes(let echoed)? = envelope.body[Self.challengeField],
        let challenge = PingChallenge(echoed)
      else { return violated() }
      guard let frame = try? send(messageType: .livenessPong, body: livenessBody(challenge))
      else { return .discarded(.trafficAfterClosed) }
      return .send(frame)

    case .livenessPong:
      guard case .bytes(let echoed)? = envelope.body[Self.challengeField],
        let challenge = PingChallenge(echoed)
      else { return violated() }
      switch liveness.receivePong(nowMilliseconds: nowMilliseconds, challenge: challenge) {
      case .accepted:
        return .livenessRestored(state.livenessRestored())

      case .ignoredUnmatched:
        return .discarded(.staleReferenceRace)
      }

    case .pairingHello, .pairingConfirm, .pairingAbort, .sessionReady:
      // Belongs to an earlier phase, so it is attributable and illegal here.
      return violated()

    case .sessionClose, .operationRequest, .operationPrepared, .operationProgress,
      .operationCommit, .operationCancel, .operationResult, .operationResultAck,
      .operationStatusRequest, .operationStatus, .error:
      return .message(envelope)
    }
  }

  /// A frame that failed to decrypt closes the session and never the pairing.
  private mutating func integrityFailed() -> RuntimeReceive {
    let outcome = state.sessionIntegrityFailed()
    liveness.close()
    channel = nil
    return .sessionClosed(outcome)
  }

  /// A frame that decrypted and then broke the protocol ends the pairing.
  private mutating func violated() -> RuntimeReceive {
    let outcome = state.authenticatedProtocolViolation()
    liveness.close()
    channel = nil
    return .pairingEnded(outcome)
  }

  private func livenessBody(_ challenge: PingChallenge) -> [String: WireValue] {
    [
      Self.challengeField: .bytes(challenge.bytes),
      Self.lastReceivedSequenceField: .unsigned(lastReceivedSequence),
    ]
  }
}
