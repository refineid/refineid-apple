// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoKit
import Foundation
import RappEngine
import Testing

@testable import RefineIDTestHost

/// Every dial whose preamble routes to a pairing served here opens a
/// session of its own, however many are open, and only what routing
/// refuses is refused (RAPP v26.10.29 §2.2.1, §8.3, STPA CC-58).
@Suite
internal struct CustodianSessionAdmissionTests {
  /// Both ends of one pairing.
  private struct Pairing {
    let custodian: RappPairRecord
    let requester: RappPairRecord
  }

  private static var profile: String { rappStreamProfileName() }

  /// A pairing between this custodian's key and a fresh computer.
  private static func pairing(custodianKey: Curve25519.KeyAgreement.PrivateKey) throws -> Pairing {
    let computerKey = Curve25519.KeyAgreement.PrivateKey()
    return Pairing(
      custodian: try RappSameAccountPairBuilder.makePairRecord(
        localStaticPrivate: custodianKey.rawRepresentation,
        localStaticPublic: custodianKey.publicKey.rawRepresentation,
        localRole: .proxy,
        remotePublicKey: computerKey.publicKey.rawRepresentation),
      requester: try RappSameAccountPairBuilder.makePairRecord(
        localStaticPrivate: computerKey.rawRepresentation,
        localStaticPublic: computerKey.publicKey.rawRepresentation,
        localRole: .requester,
        remotePublicKey: custodianKey.publicKey.rawRepresentation))
  }

  @Test("Two sessions under one pairing are both admitted")
  internal func twoSessionsOnePairing() throws {
    let pairing = try Self.pairing(custodianKey: Curve25519.KeyAgreement.PrivateKey())
    var admission = CustodianSessionAdmission()
    admission.records = [pairing.custodian]
    let app = try pairing.requester.sessionPreamble(transportProfile: Self.profile)
    let tokenExtension = try pairing.requester.sessionPreamble(transportProfile: Self.profile)
    #expect(admission.admit(app, transportProfile: Self.profile) == .open(0))
    #expect(admission.admit(tokenExtension, transportProfile: Self.profile) == .open(0))
  }

  @Test("Sessions of two pairings are both admitted, each to its own")
  internal func twoPairings() throws {
    let custodianKey = Curve25519.KeyAgreement.PrivateKey()
    let mac = try Self.pairing(custodianKey: custodianKey)
    let laptop = try Self.pairing(custodianKey: custodianKey)
    var admission = CustodianSessionAdmission()
    admission.records = [mac.custodian, laptop.custodian]
    let fromMac = try mac.requester.sessionPreamble(transportProfile: Self.profile)
    let fromLaptop = try laptop.requester.sessionPreamble(transportProfile: Self.profile)
    #expect(admission.admit(fromMac, transportProfile: Self.profile) == .open(0))
    #expect(admission.admit(fromLaptop, transportProfile: Self.profile) == .open(1))
  }

  @Test("A replayed preamble is refused; a fresh one from the same computer is not")
  internal func replayIsRefused() throws {
    let pairing = try Self.pairing(custodianKey: Curve25519.KeyAgreement.PrivateKey())
    var admission = CustodianSessionAdmission()
    admission.records = [pairing.custodian]
    let preamble = try pairing.requester.sessionPreamble(transportProfile: Self.profile)
    #expect(admission.admit(preamble, transportProfile: Self.profile) == .open(0))
    #expect(admission.admit(preamble, transportProfile: Self.profile) == .refusedUnrouted)
    let fresh = try pairing.requester.sessionPreamble(transportProfile: Self.profile)
    #expect(admission.admit(fresh, transportProfile: Self.profile) == .open(0))
  }

  @Test("A pairing preamble and a stranger's preamble are refused")
  internal func pairingAndStrangerAreRefused() throws {
    let served = try Self.pairing(custodianKey: Curve25519.KeyAgreement.PrivateKey())
    let stranger = try Self.pairing(custodianKey: Curve25519.KeyAgreement.PrivateKey())
    var admission = CustodianSessionAdmission()
    admission.records = [served.custodian]
    #expect(
      admission.admit(rappStreamPairingPreamble(), transportProfile: Self.profile)
        == .refusedPairingAttempt)
    let foreign = try stranger.requester.sessionPreamble(transportProfile: Self.profile)
    #expect(admission.admit(foreign, transportProfile: Self.profile) == .refusedUnrouted)
    #expect(
      admission.admit(Data("not a preamble".utf8), transportProfile: Self.profile)
        == .refusedUnrouted)
  }
}
