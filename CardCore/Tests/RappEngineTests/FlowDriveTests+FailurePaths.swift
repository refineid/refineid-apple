// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

extension FlowDriveTests {
  /// Unknown candidates are refused; an aborted candidate hands the offer back.
  internal func candidatePaths(_ ceremony: CeremonyState) throws {

    let twoCandidateOffer = try makeOffer(
      profiles: ceremony.everyProfile, candidates: ["stream-1", "nearby-1"])

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
        role: .requester, offer: twoCandidateOffer, candidateIdentifier: "stream-1",
        localKeys: PairKeyMaterial(), presharedKey: flowPresharedKey))
    let recoveredOffer = firstAttempt.abort()
    let fallbackPeers = try runPairing(
      offer: recoveredOffer, grants: ceremony.everyProfile, candidateIdentifier: "nearby-1")
    check(
      fallbackPeers.requester.transport.candidateIdentifier == "nearby-1",
      "an aborted candidate returns the offer and the next candidate pairs")
  }

  /// A tampered handshake frame is rejected.
  internal func tamperedHandshakeFrame(_ ceremony: CeremonyState) {
    do {
      var requester = try PairingHandshake.begin(
        .init(
          role: .requester, offer: try makeOffer(profiles: ceremony.everyProfile),
          candidateIdentifier: "stream-1", localKeys: PairKeyMaterial(),
          presharedKey: flowPresharedKey))
      var frame = try requester.writeMessage()
      frame[frame.startIndex] ^= tamperByteMask
      var proxy = try PairingHandshake.begin(
        .init(
          role: .proxy, offer: ceremony.ceremonyOffer, candidateIdentifier: "stream-1",
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
      _ = try SessionHandshake.beginProxy(pair: peers.requester)
      check(false, "the proxy side refuses a requester's record")
    } catch SessionError.roleViolation {
      check(true, "the proxy side refuses a requester's record")
    } catch {
      check(false, "the proxy side refuses a requester's record")
    }
  }

  /// A frame that fails to decrypt ends only the session.
  internal func decryptFailureEndsSession(_ peers: PairedPeers) {
    // A frame that fails to decrypt is unattributable: the session ends, the
    // pairing does not.
    do {
      var requesterHandshake = try SessionHandshake.beginRequester(
        pair: peers.requester, intent: ExplicitUserIntent())
      var proxyHandshake = try SessionHandshake.beginProxy(pair: peers.proxy)
      try proxyHandshake.readMessage(try requesterHandshake.writeMessage())
      try requesterHandshake.readMessage(try proxyHandshake.writeMessage())
      var requesterAuthentication = try requesterHandshake.intoAuthentication()
      var proxyAuthentication = try proxyHandshake.intoAuthentication()
      var tampered = try requesterAuthentication.sendReady(nonce: randomBytes(FlowLimit.readyNonce))
      tampered[tampered.startIndex] ^= tamperByteMask
      try proxyAuthentication.receiveReady(tampered)
      check(false, "a frame that fails to decrypt ends only the session")
    } catch SessionError.integrityFailure {
      check(true, "a frame that fails to decrypt ends only the session")
    } catch {
      check(false, "a frame that fails to decrypt ends only the session")
    }
  }

  /// A repeated ready ends the pairing.
  internal func repeatedReadyEndsPairing(_ peers: PairedPeers) {
    // A repeated ready is attributable to the peer, so it ends the pairing
    // rather than only the session.
    do {
      var requesterHandshake = try SessionHandshake.beginRequester(
        pair: peers.requester, intent: ExplicitUserIntent())
      var proxyHandshake = try SessionHandshake.beginProxy(pair: peers.proxy)
      try proxyHandshake.readMessage(try requesterHandshake.writeMessage())
      try requesterHandshake.readMessage(try proxyHandshake.writeMessage())
      var requesterAuthentication = try requesterHandshake.intoAuthentication()
      var proxyAuthentication = try proxyHandshake.intoAuthentication()
      let ready = try requesterAuthentication.sendReady(nonce: randomBytes(FlowLimit.readyNonce))
      try proxyAuthentication.receiveReady(ready)
      try proxyAuthentication.receiveReady(ready)
      check(false, "a repeated ready ends the pairing")
    } catch SessionError.pairingMustEnd(let cause) {
      check(cause == .duplicateReady, "a repeated ready ends the pairing")
    } catch {
      check(false, "a repeated ready ends the pairing")
    }
  }

  /// A mismatched parameter echo ends the pairing.
  internal func parameterEchoMismatch(_ peers: PairedPeers) {
    // The candidate identifier is echoed but not bound into the prologue, so
    // only the ready comparison can catch a disagreement about it.
    do {
      let divergent = try PairRecord(
        pairIdentifier: peers.proxy.pairIdentifier,
        rendezvousToken: peers.proxy.rendezvousToken,
        role: .proxy,
        localStaticPrivate: peers.proxy.localStaticPrivate,
        localStaticPublic: peers.proxy.localStaticPublic,
        remoteStaticPublic: peers.proxy.remoteStaticPublic,
        grantsHash: peers.proxy.grantsHash,
        profiles: peers.proxy.profiles,
        transport: PairTransportBinding(
          profile: peers.proxy.transport.profile, candidateIdentifier: "other-1"),
        createdAtMilliseconds: peers.proxy.createdAtMilliseconds)
      var requesterHandshake = try SessionHandshake.beginRequester(
        pair: peers.requester, intent: ExplicitUserIntent())
      var proxyHandshake = try SessionHandshake.beginProxy(pair: divergent)
      try proxyHandshake.readMessage(try requesterHandshake.writeMessage())
      try requesterHandshake.readMessage(try proxyHandshake.writeMessage())
      var requesterAuthentication = try requesterHandshake.intoAuthentication()
      var proxyAuthentication = try proxyHandshake.intoAuthentication()
      try proxyAuthentication.receiveReady(
        try requesterAuthentication.sendReady(nonce: randomBytes(FlowLimit.readyNonce)))
      check(false, "a mismatched parameter echo ends the pairing")
    } catch SessionError.pairingMustEnd(let cause) {
      check(cause == .parameterMismatch, "a mismatched parameter echo ends the pairing")
    } catch {
      check(false, "a mismatched parameter echo ends the pairing")
    }
  }

  /// A session is not healthy before both echoes verify.
  internal func sessionHealthRequiresEchoes(_ peers: PairedPeers) {
    // A session is not healthy until both echoes verify.
    do {
      var requesterHandshake = try SessionHandshake.beginRequester(
        pair: peers.requester, intent: ExplicitUserIntent())
      var proxyHandshake = try SessionHandshake.beginProxy(pair: peers.proxy)
      try proxyHandshake.readMessage(try requesterHandshake.writeMessage())
      try requesterHandshake.readMessage(try proxyHandshake.writeMessage())
      let requesterAuthentication = try requesterHandshake.intoAuthentication()
      _ = try requesterAuthentication.intoEstablished()
      check(false, "a session is not healthy before both echoes verify")
    } catch SessionError.readyIncomplete {
      check(true, "a session is not healthy before both echoes verify")
    } catch {
      check(false, "a session is not healthy before both echoes verify")
    }
  }

  /// A different pairing secret cannot complete the handshake.
  internal func negativeControl(everyProfile: [ProfileName]) {

    do {
      let offerA = try makeOffer(profiles: everyProfile)
      let offerB = try makeOffer(profiles: everyProfile)
      var requester = try PairingHandshake.begin(
        .init(
          role: .requester, offer: offerA, candidateIdentifier: "stream-1",
          localKeys: PairKeyMaterial(),
          presharedKey: flowPresharedKey))
      var proxy = try PairingHandshake.begin(
        .init(
          role: .proxy, offer: offerB, candidateIdentifier: "stream-1",
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
