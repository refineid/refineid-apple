// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

/// One first message a custodian might send, and how the requester must
/// read it.
private struct FirstMessage {
  enum Expectation {
    case closed
    case verified
    case violation
  }

  let type: MessageType
  let body: [String: WireValue]
  let expectation: Expectation
}

extension FlowDriveTests {
  /// Unknown candidates are refused; an aborted candidate hands the offer back.
  internal func candidatePaths(_ ceremony: CeremonyState) throws {

    let twoCandidateOffer = try makeOffer(
      profiles: ceremony.everyProfile, transportProfiles: [streamProfile, RappBleGattProfile.name])

    do {
      _ = try PairingHandshake.begin(
        .init(
          role: .requester, offer: twoCandidateOffer, candidateIdentifier: "absent",
          localKeys: PairKeyMaterial(), presharedKey: flowPresharedKey))
      check(false, "an unknown candidate is refused")
    } catch let failure as PairingAttemptFailure {
      check(failure.error == .candidateNotUnique, "an unknown candidate is refused")
    } catch {
      check(false, "an unknown candidate is refused")
    }

    // A failed candidate hands the offer back, and the next candidate reuses it.
    let firstAttempt = try PairingHandshake.begin(
      .init(
        role: .requester, offer: twoCandidateOffer,
        candidateIdentifier: TransportRegistry.streamCandidateIdentifier,
        localKeys: PairKeyMaterial(), presharedKey: flowPresharedKey))
    let recoveredOffer = firstAttempt.abort()
    let fallbackPeers = try runPairing(
      offer: recoveredOffer, grants: ceremony.everyProfile,
      candidateIdentifier: RappBleGattProfile.candidateId)
    check(
      fallbackPeers.requester.transport.candidateIdentifier == RappBleGattProfile.candidateId,
      "an aborted candidate returns the offer and the next candidate pairs")
  }

  /// A tampered handshake frame is rejected.
  internal func tamperedHandshakeFrame(_ ceremony: CeremonyState) {
    do {
      var requester = try PairingHandshake.begin(
        .init(
          role: .requester, offer: try makeOffer(profiles: ceremony.everyProfile),
          candidateIdentifier: TransportRegistry.streamCandidateIdentifier,
          localKeys: PairKeyMaterial(),
          presharedKey: flowPresharedKey))
      var frame = try requester.writeMessage()
      frame[frame.startIndex] ^= tamperByteMask
      var proxy = try PairingHandshake.begin(
        .init(
          role: .proxy, offer: ceremony.ceremonyOffer,
          candidateIdentifier: TransportRegistry.streamCandidateIdentifier,
          localKeys: PairKeyMaterial(),
          presharedKey: flowPresharedKey))
      try proxy.readMessage(frame)
      check(false, "a tampered handshake frame is rejected")
    } catch PairingError.noise {
      check(true, "a tampered handshake frame is rejected")
    } catch {
      check(false, "a tampered handshake frame is rejected")
    }
  }

  /// A session may be entered only from the matching stored role.
  internal func sessionRoleViolation(_ peers: PairedPeers) {
    // A session may be entered only from the matching stored role.
    do {
      _ = try SessionHandshake.beginProxy(pair: peers.requester, transportProfile: streamProfile)
      check(false, "the proxy side refuses a requester's record")
    } catch SessionError.roleViolation {
      check(true, "the proxy side refuses a requester's record")
    } catch {
      check(false, "the proxy side refuses a requester's record")
    }
  }

  /// Both endpoints' authentications over one fresh handshake.
  private func authentications(
    _ peers: PairedPeers
  ) throws -> (requester: SessionAuthentication, proxy: SessionAuthentication) {
    var requesterHandshake = try SessionHandshake.beginRequester(
      pair: peers.requester, transportProfile: streamProfile, intent: ExplicitUserIntent())
    var proxyHandshake = try SessionHandshake.beginProxy(
      pair: peers.proxy, transportProfile: streamProfile)
    try proxyHandshake.readMessage(try requesterHandshake.writeMessage())
    try requesterHandshake.readMessage(try proxyHandshake.writeMessage())
    return (try requesterHandshake.intoAuthentication(), try proxyHandshake.intoAuthentication())
  }

  /// A frame that fails to decrypt ends only the session.
  internal func decryptFailureEndsSession(_ peers: PairedPeers) {
    do {
      var (requesterAuthentication, proxyAuthentication) = try authentications(peers)
      var tampered = try proxyAuthentication.sendReady(nonce: randomBytes(FlowLimit.readyNonce))
      tampered[tampered.startIndex] ^= tamperByteMask
      check(
        try requesterAuthentication.receiveReady(tampered) == .integrityFailure,
        "a frame that fails to decrypt ends only the session")
    } catch {
      check(false, "a frame that fails to decrypt ends only the session")
    }
  }

  /// Only the custodian sends `session.ready`, once, and only the requester
  /// reads it (RAPP v26.10.22 §7.1 item 5).
  internal func readyIsTheCustodiansAlone(_ peers: PairedPeers) {
    do {
      var (requesterAuthentication, proxyAuthentication) = try authentications(peers)
      check(
        (try? requesterAuthentication.sendReady(nonce: randomBytes(FlowLimit.readyNonce))) == nil,
        "a requester never sends session.ready")
      let ready = try proxyAuthentication.sendReady(nonce: randomBytes(FlowLimit.readyNonce))
      check(
        (try? proxyAuthentication.sendReady(nonce: randomBytes(FlowLimit.readyNonce))) == nil,
        "the custodian sends session.ready once")
      check(
        (try? proxyAuthentication.receiveReady(ready)) == nil,
        "a custodian never reads session.ready")
      check(
        try requesterAuthentication.receiveReady(ready) == .verified,
        "the requester verifies the custodian's session.ready")
    } catch {
      check(false, "only the custodian sends session.ready")
    }
  }

  /// The requester reads the custodian's first message.
  ///
  /// A ready with the expected parameters verifies, a close in its place
  /// ends the session with its reason, and anything else - including a
  /// ready with other parameters - closes it with a sealed
  /// `protocol_violation` close (RAPP v26.10.22 §7.1 item 5). None of them
  /// touches the pairing.
  internal func unexpectedFirstMessageClosesTheSession(_ peers: PairedPeers) {
    do {
      let expected = SessionParameters(
        transportProfile: streamProfile,
        candidateIdentifier: TransportRegistry.streamCandidateIdentifier,
        grantsHash: peers.requester.grantsHash)
      let otherProfile = SessionParameters(
        transportProfile: RappBleGattProfile.name,
        candidateIdentifier: RappBleGattProfile.candidateId,
        grantsHash: peers.requester.grantsHash)
      let nonce = randomBytes(FlowLimit.readyNonce)
      let firstMessages = [
        FirstMessage(
          type: .sessionReady, body: try SessionReady(parameters: expected, nonce: nonce).body(),
          expectation: .verified),
        FirstMessage(
          type: .sessionClose, body: ["reason": .text(CloseReasonName.pairingRevoked)],
          expectation: .closed),
        FirstMessage(
          type: .sessionReady,
          body: try SessionReady(parameters: otherProfile, nonce: nonce).body(),
          expectation: .violation),
        FirstMessage(
          type: .livenessPing,
          body: ["challenge": .bytes(randomBytes(FlowLimit.livenessChallenge))],
          expectation: .violation),
      ]
      for first in firstMessages {
        var (custodian, requester) = matchedMessageChannels()
        var authentication = SessionAuthentication(
          role: .requester, pairIdentifier: peers.requester.pairIdentifier,
          sessionIdentifier: matchedSessionIdentifier, expectedParameters: expected,
          channel: requester)
        let outcome = try authentication.receiveReady(
          try custodian.seal(first.type, body: first.body))
        switch (outcome, first.expectation) {
        case (.verified, .verified):
          check(true, "a ready with the expected parameters verifies")

        case (.peerClosed(let reason), .closed):
          check(
            reason == .pairingRevoked,
            "a close in place of ready ends the session with its reason")

        case (.violationClosed(let notice), .violation):
          check(notice != nil, "\(first.type.rawValue) first is answered with a sealed close")

        default:
          check(false, "\(first.type.rawValue) first gives \(first.expectation)")
        }
      }
    } catch {
      check(false, "the requester reads the custodian's first message")
    }
  }

  /// A session bound to a different transport than the peer's fails.
  internal func parameterEchoMismatch(_ peers: PairedPeers) {
    // Each side binds the transport its connection uses (RAPP v26.10.22
    // §4.3 item 5), so peers disagreeing about it cannot finish the
    // handshake.
    do {
      var requesterHandshake = try SessionHandshake.beginRequester(
        pair: peers.requester, transportProfile: streamProfile, intent: ExplicitUserIntent())
      var proxyHandshake = try SessionHandshake.beginProxy(
        pair: peers.proxy, transportProfile: RappBleGattProfile.name)
      try proxyHandshake.readMessage(try requesterHandshake.writeMessage())
      check(false, "a session bound to a different transport fails")
    } catch SessionError.noise {
      check(true, "a session bound to a different transport fails")
    } catch {
      check(false, "a session bound to a different transport fails")
    }
  }

  /// A session is not healthy before `session.ready` is verified.
  internal func sessionHealthRequiresEchoes(_ peers: PairedPeers) {
    do {
      var requesterHandshake = try SessionHandshake.beginRequester(
        pair: peers.requester, transportProfile: streamProfile, intent: ExplicitUserIntent())
      var proxyHandshake = try SessionHandshake.beginProxy(
        pair: peers.proxy, transportProfile: streamProfile)
      try proxyHandshake.readMessage(try requesterHandshake.writeMessage())
      try requesterHandshake.readMessage(try proxyHandshake.writeMessage())
      let requesterAuthentication = try requesterHandshake.intoAuthentication()
      _ = try requesterAuthentication.intoEstablished()
      check(false, "a session is not healthy before ready is verified")
    } catch SessionError.readyIncomplete {
      check(true, "a session is not healthy before ready is verified")
    } catch {
      check(false, "a session is not healthy before ready is verified")
    }
  }

  /// A different pairing secret cannot complete the handshake.
  internal func negativeControl(everyProfile: [ProfileName]) {

    do {
      let offerA = try makeOffer(profiles: everyProfile)
      let offerB = try makeOffer(profiles: everyProfile)
      var requester = try PairingHandshake.begin(
        .init(
          role: .requester, offer: offerA,
          candidateIdentifier: TransportRegistry.streamCandidateIdentifier,
          localKeys: PairKeyMaterial(),
          presharedKey: flowPresharedKey))
      var proxy = try PairingHandshake.begin(
        .init(
          role: .proxy, offer: offerB,
          candidateIdentifier: TransportRegistry.streamCandidateIdentifier,
          localKeys: PairKeyMaterial(),
          presharedKey: flowPresharedKey))
      try proxy.readMessage(try requester.writeMessage())
      try requester.readMessage(try proxy.writeMessage())
      try proxy.readMessage(try requester.writeMessage())
      check(false, "a different pairing secret cannot complete the handshake")
    } catch PairingError.noise {
      check(true, "a different pairing secret cannot complete the handshake")
    } catch {
      check(false, "a different pairing secret cannot complete the handshake")
    }
  }
}
