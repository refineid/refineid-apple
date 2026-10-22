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

internal let streamProfile = "fi.refineid.stream"

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
  try runPairing(
    offer: offer, grants: grants,
    candidateIdentifier: TransportRegistry.streamCandidateIdentifier)
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

  let requesterPairIdentifier = requesterConfirmation.pairIdentifier
  let proxyPairIdentifier = proxyConfirmation.pairIdentifier
  // Both store their record, then confirm it to each other (RAPP
  // v26.10.22 §4.3 item 4); only both confirmations make a pairing active.
  var (requesterRecord, requesterStorage) = try requesterConfirmation.intoStorage(
    createdAtMilliseconds: FlowFixture.createdAtMilliseconds)
  var (proxyRecord, proxyStorage) = try proxyConfirmation.intoStorage(
    createdAtMilliseconds: FlowFixture.createdAtMilliseconds)
  let requesterStored = try requesterStorage.sendStored()
  let proxyStored = try proxyStorage.sendStored()
  try proxyStorage.receiveStored(requesterStored)
  try requesterStorage.receiveStored(proxyStored)
  requesterRecord = try requesterStorage.intoActive().confirm(requesterRecord)
  proxyRecord = try proxyStorage.intoActive().confirm(proxyRecord)

  return PairedPeers(
    requester: requesterRecord,
    proxy: proxyRecord,
    requesterPairIdentifier: requesterPairIdentifier,
    proxyPairIdentifier: proxyPairIdentifier)
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

  // Only the custodian sends session.ready; the requester verifies it
  // (RAPP v26.10.22 §7.1 item 5).
  let outcome = try requesterAuthentication.receiveReady(
    try proxyAuthentication.sendReady(nonce: randomBytes(FlowLimit.readyNonce)))
  guard outcome == .verified else { throw SessionError.readyIncomplete }

  return (
    try requesterAuthentication.intoEstablished(), try proxyAuthentication.intoEstablished()
  )
}

/// The filler byte of the key a matched channel pair shares.
private let matchedChannelKeyFiller: UInt8 = 0x2B

/// The filler byte of the session identifier a matched channel pair names.
private let matchedSessionFiller: UInt8 = 0x3C

/// The session identifier ``matchedMessageChannels()`` names.
internal let matchedSessionIdentifier = filler(
  matchedSessionFiller, WireLimits.sessionIdentifier)

/// Two envelope channels where whatever the first seals, the second opens at
/// sequence 0: a peer's first message without running a handshake.
internal func matchedMessageChannels() -> (sender: RappMessageChannel, receiver: RappMessageChannel)
{
  let key = filler(matchedChannelKeyFiller, NoiseSizes.keyLength)
  var send = NoiseCipherState()
  var receive = NoiseCipherState()
  send.initializeKey(key)
  receive.initializeKey(key)
  return (
    RappMessageChannel(
      channel: RappSecureChannel(send: send, receive: receive),
      sessionIdentifier: matchedSessionIdentifier),
    RappMessageChannel(
      channel: RappSecureChannel(send: send, receive: receive),
      sessionIdentifier: matchedSessionIdentifier)
  )
}
