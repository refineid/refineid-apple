// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
//
// The shared ceremony: pairing two fresh endpoints and establishing a
// session over the pair, for every suite that needs a live channel.

import Foundation
import Testing

@testable import RappEngine

internal func check(_ passed: Bool, _ label: String) {
  #expect(passed, "\(label)")
}

/// Flips every bit it touches: the tamper the failure paths drive.
internal let tamperByteMask: UInt8 = 0xff

internal func randomBytes(_ count: Int) -> Data {
  var generator = SystemRandomNumberGenerator()
  return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
}

internal let streamProfile = "fi.refineid.stream.v1"

internal func makeOffer(profiles: [ProfileName]) throws -> PairingOffer {
  try makeOffer(
    profiles: profiles, candidates: ["stream-1"],
    lifetimeMilliseconds: OfferLimit.offerLifetimeMaximumMilliseconds)
}

internal func makeOffer(
  profiles: [ProfileName], lifetimeMilliseconds: UInt64
) throws -> PairingOffer {
  try makeOffer(
    profiles: profiles, candidates: ["stream-1"],
    lifetimeMilliseconds: lifetimeMilliseconds)
}

internal func makeOffer(
  profiles: [ProfileName], candidates: [String]
) throws -> PairingOffer {
  try makeOffer(
    profiles: profiles, candidates: candidates,
    lifetimeMilliseconds: OfferLimit.offerLifetimeMaximumMilliseconds)
}

internal func makeOffer(
  profiles: [ProfileName],
  candidates: [String],
  lifetimeMilliseconds: UInt64
) throws -> PairingOffer {
  try PairingOffer(
    offerIdentifier: randomBytes(OfferLimit.offerIdentifierSize),
    pairingSecret: randomBytes(OfferLimit.pairingSecretSize),
    suites: [mandatoryPairingSuite],
    profiles: profiles.map(\.rawValue),
    transports: candidates.map { candidate in
      TransportCandidate(profile: streamProfile, candidateIdentifier: candidate)
    },
    offerLifetimeMilliseconds: lifetimeMilliseconds)
}

/// Runs the whole ceremony between two fresh endpoints.
internal func runPairing(
  offer: PairingOffer, grants: [ProfileName]
) throws -> PairedPeers {
  try runPairing(
    offer: offer, grants: grants, candidateIdentifier: "stream-1", nowMilliseconds: 0)
}

internal func runPairing(
  offer: PairingOffer, grants: [ProfileName], candidateIdentifier: String
) throws -> PairedPeers {
  try runPairing(
    offer: offer, grants: grants, candidateIdentifier: candidateIdentifier,
    nowMilliseconds: 0)
}

internal func runPairing(
  offer: PairingOffer, grants: [ProfileName], nowMilliseconds: UInt64
) throws -> PairedPeers {
  try runPairing(
    offer: offer, grants: grants, candidateIdentifier: "stream-1",
    nowMilliseconds: nowMilliseconds)
}

internal func runPairing(
  offer: PairingOffer,
  grants: [ProfileName],
  candidateIdentifier: String,
  nowMilliseconds: UInt64
) throws -> PairedPeers {
  let deadline = try PairingOfferDeadline(offer: offer, startedAtMilliseconds: 0)
  var requester = try PairingHandshake.begin(
    .init(
      role: .requester, offer: offer, candidateIdentifier: candidateIdentifier,
      localKeys: PairKeyMaterial(), deadline: deadline, nowMilliseconds: nowMilliseconds))
  var proxy = try PairingHandshake.begin(
    .init(
      role: .proxy, offer: offer, candidateIdentifier: candidateIdentifier,
      localKeys: PairKeyMaterial(), deadline: deadline, nowMilliseconds: nowMilliseconds))

  try proxy.readMessage(try requester.writeMessage())
  try requester.readMessage(try proxy.writeMessage())
  try proxy.readMessage(try requester.writeMessage())

  var requesterConfirmation = try requester.intoConfirmation()
  var proxyConfirmation = try proxy.intoConfirmation()

  let requesterHello = try requesterConfirmation.sendHello(
    displayName: "RefineID iPad", platform: "iPadOS")
  _ = try proxyConfirmation.receiveHello(requesterHello)
  let proxyHello = try proxyConfirmation.sendHello(
    displayName: "RefineID iPhone", platform: "iOS")
  _ = try requesterConfirmation.receiveHello(proxyHello)

  let proxyConfirm = try proxyConfirmation.sendConfirmation(grantedProfiles: grants)
  _ = try requesterConfirmation.receiveConfirmation(proxyConfirm)
  let requesterConfirm = try requesterConfirmation.sendConfirmation(grantedProfiles: grants)
  _ = try proxyConfirmation.receiveConfirmation(requesterConfirm)

  return PairedPeers(
    requester: try requesterConfirmation.intoPairRecord(
      createdAtMilliseconds: FlowFixture.createdAtMilliseconds),
    proxy: try proxyConfirmation.intoPairRecord(
      createdAtMilliseconds: FlowFixture.createdAtMilliseconds),
    requesterPairIdentifier: requesterConfirmation.pairIdentifier,
    proxyPairIdentifier: proxyConfirmation.pairIdentifier)
}

/// Establishes a session over a completed pairing.
internal func runSession(
  _ peers: PairedPeers
) throws -> (requester: EstablishedSession, proxy: EstablishedSession) {
  var requester = try SessionHandshake.beginRequester(
    pair: peers.requester, intent: ExplicitUserIntent())
  var proxy = try SessionHandshake.beginProxy(pair: peers.proxy)

  try proxy.readMessage(try requester.writeMessage())
  try requester.readMessage(try proxy.writeMessage())

  var requesterAuthentication = try requester.intoAuthentication()
  var proxyAuthentication = try proxy.intoAuthentication()

  try proxyAuthentication.receiveReady(
    try requesterAuthentication.sendReady(nonce: randomBytes(FlowLimit.readyNonce)))
  try requesterAuthentication.receiveReady(
    try proxyAuthentication.sendReady(nonce: randomBytes(FlowLimit.readyNonce)))

  return (
    try requesterAuthentication.intoEstablished(), try proxyAuthentication.intoEstablished()
  )
}
