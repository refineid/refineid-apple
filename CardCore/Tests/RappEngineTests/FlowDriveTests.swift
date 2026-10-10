// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
//
// Both endpoints complete pairing and a session in one process

import CryptoKit
import Foundation
import Testing

@testable import RappEngine

// The scenario runs as one continuous drive, because that is what it proves:
// each step depends on the state the previous one left, and a peer answers a
// real predecessor rather than a fixture. Splitting it into separate tests
// would thread that state through setup and stop testing the sequence.
@Suite("RAPP pairing and session flows")
internal struct FlowDriveTests {
  /// The ceremony state later steps replay against.
  internal struct CeremonyState {
    internal let everyProfile: [ProfileName]
    internal let ceremonyOffer: PairingOffer
    internal let peers: PairedPeers
  }

  @Test("Both endpoints complete pairing and a session in one process")
  internal func run() throws {
    let ceremony = try pairingCeremony()
    try sessionOverPairing(ceremony.peers)
    try grants(ceremony)
    try offerExpiry(everyProfile: ceremony.everyProfile)
    try liveness()
    try candidatePaths(ceremony)
    tamperedHandshakeFrame(ceremony)
    sessionRoleViolation(ceremony.peers)
    decryptFailureEndsSession(ceremony.peers)
    repeatedReadyEndsPairing(ceremony.peers)
    parameterEchoMismatch(ceremony.peers)
    sessionHealthRequiresEchoes(ceremony.peers)
    negativeControl(everyProfile: ceremony.everyProfile)
  }

  /// Re-encoding one record with the other's role-specific fields
  /// reproduces it byte for byte.
  private func checkMirroredRecord(_ peers: PairedPeers) throws {
    let mirrored = try PairRecord(
      pairIdentifier: peers.proxy.pairIdentifier,
      rendezvousToken: peers.proxy.rendezvousToken,
      role: .requester,
      localStaticPrivate: peers.requester.localStaticPrivate,
      localStaticPublic: peers.requester.localStaticPublic,
      remoteStaticPublic: peers.requester.remoteStaticPublic,
      grantsHash: peers.proxy.grantsHash,
      profiles: peers.proxy.profiles,
      transport: peers.proxy.transport,
      createdAtMilliseconds: peers.proxy.createdAtMilliseconds)
    check(
      (try mirrored.encoded()) == (try peers.requester.encoded()),
      "the records match byte for byte outside role and key ownership")
  }

  /// The pairing ceremony both endpoints complete.
  private func pairingCeremony() throws -> CeremonyState {

    let everyProfile: [ProfileName] = [.cardStatus, .authentication, .documentSigning]
    let ceremonyOffer = try makeOffer(profiles: everyProfile)
    let peers = try runPairing(offer: ceremonyOffer, grants: everyProfile)

    check(
      peers.requesterPairIdentifier == peers.proxyPairIdentifier,
      "both sides derive one pair identifier")
    check(
      peers.requester.pairIdentifier == peers.proxy.pairIdentifier,
      "the record carries that identifier")
    check(
      peers.requester.rendezvousToken == peers.proxy.rendezvousToken,
      "both derive one rendezvous token")
    check(peers.requester.grantsHash == peers.proxy.grantsHash, "both derive one grants hash")
    check(peers.requester.profiles == peers.proxy.profiles, "both agree on the granted profiles")
    check(
      peers.requester.grantsHash
        == (try RappHashes.grantsHash(profiles: everyProfile.map(\.rawValue))),
      "the grants hash is the digest of the granted set")
    check(
      peers.requester.role == .requester && peers.proxy.role == .proxy,
      "each side stores its own role")
    check(
      peers.requester.localStaticPublic == peers.proxy.remoteStaticPublic
        && peers.proxy.localStaticPublic == peers.requester.remoteStaticPublic,
      "each side authenticated the other's static key")
    check(
      peers.requester.transport == peers.proxy.transport, "both bind the same transport candidate")

    // The stored order is fixed by the name bytes, so the record encodes the
    // same way on both peers and matches the reference engine.
    check(
      peers.requester.profiles == [.authentication, .cardStatus, .documentSigning],
      "granted profiles are stored ordered by their name bytes")

    // The two records differ only in role and key ownership, so re-encoding one
    // with the other's role-specific fields must reproduce it byte for byte.
    try checkMirroredRecord(peers)
    return CeremonyState(
      everyProfile: everyProfile, ceremonyOffer: ceremonyOffer, peers: peers)
  }

  /// A session over the stored pairing.
  private func sessionOverPairing(_ peers: PairedPeers) throws {

    var (requesterSession, proxySession) = try runSession(peers)
    check(
      requesterSession.sessionIdentifier == proxySession.sessionIdentifier,
      "both sides derive one session identifier")
    check(
      requesterSession.sessionIdentifier != peers.requester.pairIdentifier,
      "the session identifier is not the pair identifier")

    // The slim relay's channel: a payload with no envelope over it, which
    // brings its own correlation and needs the cipher and nothing else.
    let slim = Data("one request".utf8)
    check(
      try proxySession.openPayload(try requesterSession.sealPayload(slim)) == slim
        && (try requesterSession.openPayload(try proxySession.sealPayload(slim))) == slim,
      "an opaque payload crosses the session both ways unchanged")

    let challenge = randomBytes(FlowLimit.livenessChallenge)
    let pingFrame = try requesterSession.seal(
      .livenessPing, body: ["challenge": .bytes(challenge), "last_received_sequence": .unsigned(0)])
    let openedPing = try proxySession.open(pingFrame)
    check(openedPing.messageType == .livenessPing, "a sealed message opens on the other side")
    check(openedPing.body["challenge"] == .bytes(challenge), "the payload survives the channel")
  }

  /// Grant subsets, and refusals outside the offer.
  private func grants(_ ceremony: CeremonyState) throws {

    let intersection = grantIntersection(
      offered: ceremony.everyProfile, requested: [.cardStatus, .authentication])
    check(
      intersection == sortedByNameBytes([.cardStatus, .authentication]),
      "the intersection is the common set")

    let subsetPeers = try runPairing(
      offer: try makeOffer(profiles: ceremony.everyProfile), grants: intersection)
    check(subsetPeers.requester.profiles == intersection, "a granted subset is what gets stored")
    check(
      subsetPeers.requester.grantsHash != ceremony.peers.requester.grantsHash,
      "a different grant set hashes differently")

    do {
      _ = try runPairing(offer: try makeOffer(profiles: ceremony.everyProfile), grants: [])
      check(false, "an empty grant set is refused")
    } catch PairingError.invalidGrantSet {
      check(true, "an empty grant set is refused")
    } catch {
      check(false, "an empty grant set is refused")
    }

    do {
      _ = try runPairing(offer: try makeOffer(profiles: [.cardStatus]), grants: [.documentSigning])
      check(false, "a grant outside the offered set is refused")
    } catch PairingError.invalidGrantSet {
      check(true, "a grant outside the offered set is refused")
    } catch {
      check(false, "a grant outside the offered set is refused")
    }
  }

  /// Offer lifetimes admit and refuse.
  private func offerExpiry(everyProfile: [ProfileName]) throws {
    let shortLifetime = OfferLimit.offerLifetimeMilliseconds
    let expiringOffer = try makeOffer(profiles: everyProfile)
    let expiringDeadline = try PairingOfferDeadline(offer: expiringOffer, startedAtMilliseconds: 0)
    check(
      expiringDeadline.isLive(nowMilliseconds: shortLifetime - 1),
      "the offer is live just inside its lifetime")
    check(
      !expiringDeadline.isLive(nowMilliseconds: shortLifetime),
      "the offer is dead once the lifetime elapses")

    let bridge = try RappPairingBridge.custodianOffer(
      pairingCode: "7KX4M9", offerId: randomBytes(OfferLimit.offerIdentifierSize),
      profiles: everyProfile.map(\.rawValue), transportProfiles: [streamProfile],
      startedAtMonotonicMs: 0)
    do {
      try bridge.beginCpace(
        candidateId: "stream-1", randomBytes64: randomBytes(RappCpaceConstants.wideScalarSize),
        nowMonotonicMs: shortLifetime)
      check(false, "a ceremony started after the deadline is refused")
    } catch RappBindingError.OfferExpired {
      check(true, "a ceremony started after the deadline is refused")
    } catch {
      check(false, "a ceremony started after the deadline is refused")
    }
    try bridge.beginCpace(
      candidateId: "stream-1", randomBytes64: randomBytes(RappCpaceConstants.wideScalarSize),
      nowMonotonicMs: shortLifetime - 1)
    check(true, "a ceremony started just inside the deadline begins")
  }

  /// Liveness probes, echoes and mismatches.
  private func liveness() throws {

    // The tracker owns the schedule, so a probe is registered by polling it.
    let policy = LivenessConfiguration(
      baseIntervalMilliseconds: 1_000, responseTimeoutMilliseconds: 500,
      maximumIntervalMilliseconds: 8_000, maximumJitterMilliseconds: 100, maximumMisses: 3)
    var tracker = try LivenessTracker(configuration: policy, nowMilliseconds: 0)
    let outstanding = try #require(PingChallenge(randomBytes(PingChallenge.byteCount)))
    let other = try #require(PingChallenge(randomBytes(PingChallenge.byteCount)))
    check(
      tracker.receivePong(nowMilliseconds: 0, challenge: outstanding) == .ignoredUnmatched,
      "a pong with no ping proves nothing")
    check(
      tracker.poll(nowMilliseconds: 1_000, nextChallenge: outstanding, jitterMilliseconds: 0)
        == .sendPing(outstanding), "a due probe sends the challenge")
    check(
      tracker.receivePong(nowMilliseconds: 1_010, challenge: other) == .ignoredUnmatched,
      "a mismatched echo is discarded")
    check(tracker.hasOutstandingChallenge, "the challenge stays outstanding after a mismatch")
    check(
      tracker.receivePong(nowMilliseconds: 1_020, challenge: outstanding) == .accepted,
      "the exact echo proves liveness")
    check(!tracker.hasOutstandingChallenge, "an accepted echo clears the challenge")
    check(
      tracker.receivePong(nowMilliseconds: 1_030, challenge: outstanding) == .ignoredUnmatched,
      "the same echo does not prove liveness twice")
  }

}
