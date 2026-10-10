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
  try makeOffer(profiles: profiles, transportProfiles: [streamProfile])
}

internal func makeOffer(
  profiles: [ProfileName], transportProfiles: [String]
) throws -> PairingOffer {
  try PairingOffer.create(
    offerIdentifier: randomBytes(OfferLimit.offerIdentifierSize),
    profiles: profiles.map(\.rawValue),
    transportProfiles: transportProfiles)
}

/// The filler byte of the CPace key the Noise-only drives share.
private let presharedKeyFiller: UInt8 = 0x5A

/// The CPace key the Noise-only drives share.
internal let flowPresharedKey = filler(presharedKeyFiller, NoiseSizes.keyLength)

/// Runs the whole ceremony between two fresh endpoints.
internal func runPairing(
  offer: PairingOffer, grants: [ProfileName]
) throws -> PairedPeers {
  try runPairing(offer: offer, grants: grants, candidateIdentifier: "stream-1")
}

/// Runs the Noise_XXpsk3 handshake and the pairing channel over a shared key.
internal func runPairing(
  offer: PairingOffer,
  grants: [ProfileName],
  candidateIdentifier: String
) throws -> PairedPeers {
  let presharedKey = flowPresharedKey
  var requester = try PairingHandshake.begin(
    .init(
      role: .requester, offer: offer, candidateIdentifier: candidateIdentifier,
      localKeys: PairKeyMaterial(), presharedKey: presharedKey))
  var proxy = try PairingHandshake.begin(
    .init(
      role: .proxy, offer: offer, candidateIdentifier: candidateIdentifier,
      localKeys: PairKeyMaterial(), presharedKey: presharedKey))

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
    pair: peers.requester, transportProfile: streamProfile, intent: ExplicitUserIntent())
  var proxy = try SessionHandshake.beginProxy(pair: peers.proxy, transportProfile: streamProfile)

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
