// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// A session whose handshake completed and whose `session.ready` has not yet
/// been sent or verified (RAPP v26.10.21 §7.1 item 5).
///
/// The custodian sends `session.ready` on completing the handshake; the
/// requester verifies it, or reads a `session.close` in its place. Anything
/// else first, or mismatched parameters, closes the session with a sealed
/// `protocol_violation` close.
internal struct SessionAuthentication {
  private let role: EndpointRole
  private let pairIdentifier: Data
  internal let sessionIdentifier: Data
  private let expectedParameters: SessionParameters
  private var channel: RappMessageChannel?
  private var ready = false

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
  /// fresh nonce.
  internal mutating func sendReady(nonce: Data) throws -> Data {
    guard role == .proxy else { throw SessionError.roleViolation }
    guard !ready else { throw SessionError.duplicateReady }
    let body: [String: WireValue]
    do {
      body = try SessionReady(parameters: expectedParameters, nonce: nonce).body()
    } catch let error as MessageFieldError {
      throw SessionError.message(error)
    }
    let frame = try seal(.sessionReady, body: body)
    ready = true
    return frame
  }

  /// The requester reads the custodian's first message.
  internal mutating func receiveReady(_ frame: Data) throws -> RappReadyOutcome {
    guard role == .requester else { throw SessionError.roleViolation }
    guard !ready else { throw SessionError.duplicateReady }
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
      guard let received = try? SessionReady.from(body: envelope.body),
        received.parameters == expectedParameters
      else { return closeForViolation() }
      ready = true
      return .verified

    case .sessionClose:
      channel = nil
      guard case .text(let name)? = envelope.body["reason"],
        let reason = RappCloseReason(rawValue: name)
      else { return .violationClosed(notice: nil) }
      return .peerClosed(reason)

    default:
      return closeForViolation()
    }
  }

  /// The first and only message of a session over a forgotten record: the
  /// sealed `session.close` with reason `pairing_revoked`, in place of
  /// `session.ready` on the custodian and before anything else on the
  /// requester (§4.6 item 2).
  ///
  /// The channel closes with it.
  internal mutating func sendRevocationNotice() throws -> Data {
    guard !ready else { throw SessionError.duplicateReady }
    defer { channel = nil }
    return try seal(.sessionClose, body: ["reason": .text(CloseReasonName.pairingRevoked)])
  }

  /// Promotes to a healthy session once `session.ready` was sent or
  /// verified.
  internal consuming func intoEstablished() throws -> EstablishedSession {
    guard ready else { throw SessionError.readyIncomplete }
    guard let channel else { throw SessionError.closed }
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

  private mutating func closeForViolation() -> RappReadyOutcome {
    let notice = try? seal(
      .sessionClose, body: ["reason": .text(CloseReasonName.protocolViolation)])
    channel = nil
    return .violationClosed(notice: notice)
  }
}
