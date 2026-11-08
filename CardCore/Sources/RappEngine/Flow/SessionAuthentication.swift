// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// A session whose handshake completed and whose `session.ready` has not yet
/// been sent or verified (RAPP v26.11.8 §7.1 item 5).
///
/// The custodian sends `session.ready` on completing the handshake; the
/// requester verifies it and answers with `session.hello`, or reads a
/// `session.close` in its place and echoes it. Anything else first, or
/// mismatched parameters or name, closes the session with a sealed
/// `protocol_violation` close, whose echo the sender then waits for.
internal struct SessionAuthentication {
  private let role: EndpointRole
  private let pairIdentifier: Data
  internal let sessionIdentifier: Data
  private let expectedParameters: SessionParameters
  private var channel: RappMessageChannel?
  private var ready = false
  /// This endpoint sent its close and waits for the peer's echo.
  private var awaitingEcho = false

  internal init(
    role: EndpointRole,
    pairIdentifier: Data,
    sessionIdentifier: Data,
    expectedParameters: SessionParameters,
    channel: RappMessageChannel
  ) {
    self.role = role
    self.pairIdentifier = pairIdentifier
    self.sessionIdentifier = sessionIdentifier
    self.expectedParameters = expectedParameters
    self.channel = channel
  }

  /// The custodian's `session.ready`: the exact session parameters with a
  /// fresh nonce and its current display name.
  internal mutating func sendReady(nonce: Data, displayName: RappDisplayName) throws -> Data {
    guard role == .proxy else { throw SessionError.roleViolation }
    guard !ready, !awaitingEcho else { throw SessionError.duplicateReady }
    let body: [String: WireValue]
    do {
      body = try SessionReady(
        parameters: expectedParameters, nonce: nonce, displayName: displayName
      ).body()
    } catch let error as MessageFieldError {
      throw SessionError.message(error)
    }
    let frame = try seal(.sessionReady, body: body)
    ready = true
    return frame
  }

  /// The requester reads the custodian's first message.
  ///
  /// A verified `session.ready` is answered with `session.hello` carrying `displayName`, the
  /// requester's current name, as the session's first message (§7.1 item 6); a `session.close` in
  /// its place is answered with its echo (§7.1 item 7).
  internal mutating func receiveReady(
    _ frame: Data, displayName: RappDisplayName
  ) throws -> RappReadyOutcome {
    guard role == .requester else { throw SessionError.roleViolation }
    guard !ready, !awaitingEcho else { throw SessionError.duplicateReady }
    guard var working = channel else { throw SessionError.closed }
    let envelope: Envelope
    do {
      envelope = try working.open(frame)
    } catch RappOpenFailure.sessionIntegrityFailure {
      channel = nil
      return .integrityFailure
    } catch {
      channel = working
      return closeForViolation()
    }
    channel = working
    switch envelope.messageType {
    case .sessionReady:
      return verify(envelope, answeringWith: displayName)

    case .sessionClose:
      guard let reason = closeReason(of: envelope) else { return closeForViolation() }
      let echo = try? seal(.sessionClose, body: ["reason": .text(reason.rawValue)])
      channel = nil
      return .peerClosed(reason, echo: echo)

    default:
      return closeForViolation()
    }
  }

  /// Verifies the custodian's `session.ready` and seals the requester's
  /// `session.hello` carrying `displayName`.
  private mutating func verify(
    _ envelope: Envelope, answeringWith displayName: RappDisplayName
  ) -> RappReadyOutcome {
    guard let received = try? SessionReady.from(body: envelope.body),
      received.parameters == expectedParameters
    else { return closeForViolation() }
    guard
      let hello = try? seal(.sessionHello, body: SessionHello(displayName: displayName).body())
    else {
      channel = nil
      return .integrityFailure
    }
    ready = true
    return .verified(peerDisplayName: received.displayName, hello: hello)
  }

  /// The first and only message of a session over a forgotten record: the
  /// sealed `session.close` with reason `pairing_revoked`, in place of
  /// `session.ready` on the custodian and before anything else on the
  /// requester (§4.6 item 2).
  ///
  /// The channel stays open for the peer's echo (§7.1 item 7), read with
  /// ``receiveCloseEcho(_:)``.
  internal mutating func sendRevocationNotice() throws -> Data {
    guard !ready, !awaitingEcho else { throw SessionError.duplicateReady }
    let notice = try seal(
      .sessionClose, body: ["reason": .text(CloseReasonName.pairingRevoked)])
    awaitingEcho = true
    return notice
  }

  /// Reads one frame while this endpoint waits for the echo of its own
  /// close: a `session.close`, whatever its reason, is the echo or a close
  /// that crossed this endpoint's, and is never answered; anything else is
  /// ignored (§7.1 item 7).
  internal mutating func receiveCloseEcho(_ frame: Data) -> RappCloseEcho {
    guard awaitingEcho, var working = channel else { return .ended }
    guard let envelope = try? working.open(frame) else {
      channel = nil
      awaitingEcho = false
      return .ended
    }
    channel = working
    guard envelope.messageType == .sessionClose else { return .ignored }
    channel = nil
    awaitingEcho = false
    guard let reason = closeReason(of: envelope) else { return .ended }
    return .acknowledged(reason)
  }

  /// Promotes to a healthy session once `session.ready` was sent or
  /// verified.
  internal consuming func intoEstablished() throws -> EstablishedSession {
    guard ready else { throw SessionError.readyIncomplete }
    guard !awaitingEcho, let channel else { throw SessionError.closed }
    return EstablishedSession(
      role: role, pairIdentifier: pairIdentifier, sessionIdentifier: sessionIdentifier,
      channel: channel)
  }

  private mutating func seal(_ messageType: MessageType, body: [String: WireValue]) throws
    -> Data
  {
    guard var working = channel else { throw SessionError.closed }
    let frame: Data
    do {
      frame = try working.seal(messageType, body: body)
    } catch {
      throw SessionError.noise
    }
    channel = working
    return frame
  }

  /// Seals the `protocol_violation` close and waits for its echo; without
  /// a sealed close the channel ends at once.
  private mutating func closeForViolation() -> RappReadyOutcome {
    guard
      let notice = try? seal(
        .sessionClose, body: ["reason": .text(CloseReasonName.protocolViolation)])
    else {
      channel = nil
      return .violationClosed(notice: nil)
    }
    awaitingEcho = true
    return .violationClosed(notice: notice)
  }

  private func closeReason(of envelope: Envelope) -> RappCloseReason? {
    guard case .text(let name)? = envelope.body["reason"] else { return nil }
    return RappCloseReason(rawValue: name)
  }
}
