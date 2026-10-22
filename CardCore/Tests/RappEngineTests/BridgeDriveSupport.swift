// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
//
// Two endpoints in one process, each behind the bridges the platform layers
// call: pairing records, a session handshake, session.ready, and the
// operation bridges carrying frames between them.

import Foundation
import Testing

@testable import RappEngine

/// Every credential profile, for pairings that grant all of them.
internal let everyProfile: [ProfileName] = [.cardStatus, .authentication, .documentSigning]

/// Both session bridges, through the handshake and into `session.ready`.
internal func authenticatingSessions(
  _ pairing: PairedBridges
) throws -> (requester: RappSessionBridge, custodian: RappSessionBridge) {
  let requester = try RappSessionBridge.beginRequester(
    pair: pairing.requester, transportProfile: StreamProfile.name)
  let custodian = try RappSessionBridge.beginProxy(
    pair: pairing.custodian, transportProfile: StreamProfile.name)
  try custodian.readHandshakeFrame(bytes: try requester.writeHandshakeFrame())
  try requester.readHandshakeFrame(bytes: try custodian.writeHandshakeFrame())
  #expect(try requester.handshakeComplete() && custodian.handshakeComplete())
  try requester.enterAuthentication()
  try custodian.enterAuthentication()
  return (requester, custodian)
}

/// A session established over `pairing`: the custodian sends
/// `session.ready`, the requester verifies it, and both take operations
/// from `nowMilliseconds` on.
internal func establishedSession(
  _ pairing: PairedBridges, nowMilliseconds: UInt64
) throws -> LiveSession {
  let (requester, custodian) = try authenticatingSessions(pairing)
  let ready = try custodian.sendReady(nonce: randomBytes(FlowLimit.readyNonce))
  try custodian.enterEstablished()
  guard try requester.receiveReady(bytes: ready) == .verified else {
    throw DriveFailure(description: "the requester verifies the custodian's ready")
  }
  try requester.enterEstablished()
  #expect(requester.isEstablished() && custodian.isEstablished())
  return LiveSession(
    requester: try RappOperationBridge.beginRequester(
      session: requester, maximumLifetimeMs: OperationFixture.maximumLifetimeMilliseconds,
      nowMs: nowMilliseconds),
    custodian: try RappOperationBridge.beginProxy(
      session: custodian, maximumLifetimeMs: OperationFixture.maximumLifetimeMilliseconds,
      nowMs: nowMilliseconds))
}

/// The sealed frame a step releases.
internal func frame(_ action: RappBridgeAction) throws -> Data {
  switch action {
  case .sendFrame(let frame, _), .sendClose(let frame, _, _):
    return frame

  default:
    throw DriveFailure(description: "expected a frame, got \(action)")
  }
}

/// Delivers the frame `action` releases to `bridge`.
internal func deliver(
  _ action: RappBridgeAction, to bridge: RappOperationBridge, at nowMilliseconds: UInt64
) throws -> RappBridgeAction {
  try bridge.receiveFrame(bytes: try frame(action), nowMs: nowMilliseconds)
}

/// Seals a message on a bridge's session the way a nonconforming peer would.
///
/// The `body` goes out as `messageType` on `bridge`'s session.
internal func injected(
  _ messageType: MessageType, _ body: [String: WireValue], from bridge: RappOperationBridge
) throws -> Data {
  try bridge.locked { try bridge.session.seal(messageType, body: body) }
}

/// Opens a frame from the peer without letting the bridge act on it.
///
/// The frame is one `bridge`'s peer sealed; the cipher state stays in step.
internal func opened(_ frame: Data, by bridge: RappOperationBridge) throws -> Envelope {
  try bridge.locked { try bridge.session.open(frame) }
}

/// A browser authentication request for `identifier`.
internal func browserRequest(
  _ identifier: RappOperationIdentifier, expiresAfterMilliseconds: UInt64
) throws -> OperationRequest {
  try OperationRequest(
    operationIdentifier: identifier, profile: .authentication,
    localStartMilliseconds: OperationFixture.startMilliseconds,
    expiresAfterMilliseconds: expiresAfterMilliseconds,
    operation: .browserAuthenticate(
      origin: OperationFixture.origin, keyProfile: .ecdsaP256, algorithm: .ecdsaSha256,
      digest: OperationFixture.digest))
}

/// An inspection request for `identifier`.
internal func inspectionRequest(_ identifier: RappOperationIdentifier) throws -> OperationRequest {
  try OperationRequest(
    operationIdentifier: identifier, profile: .cardStatus,
    localStartMilliseconds: OperationFixture.startMilliseconds,
    expiresAfterMilliseconds: OperationFixture.lifetimeMilliseconds, operation: .inspectCard)
}
