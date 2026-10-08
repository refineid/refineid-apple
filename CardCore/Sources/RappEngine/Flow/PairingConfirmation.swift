// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

// The offered profiles stay optional for the same reason the hello does:
// absent and empty are different bytes on the wire.
/// The authenticated pairing channel, awaiting both hellos and two equal
/// grant confirmations.
internal struct PairingConfirmation {
  private let role: EndpointRole

  internal let pairIdentifier: Data

  private let rendezvousToken: Data

  private let offerHash: Data

  private let candidate: TransportCandidate

  private let offeredProfiles: [ProfileName]

  private let localKeys: PairKeyMaterial

  private let remoteStaticPublic: Data

  private var channel: RappMessageChannel

  private var localHelloSent = false

  private var peerHello: PairingHello?

  private var localGrants: [ProfileName] = []

  private var localConfirmationSent = false

  private var peerGrants: [ProfileName] = []

  private var peerConfirmationReceived = false

  private var localParameters: NegotiatedParameters {
    NegotiatedParameters(
      offerHash: offerHash, transportProfile: candidate.profile,
      candidateIdentifier: candidate.candidateIdentifier)
  }

  internal init(
    role: EndpointRole,
    pairIdentifier: Data,
    rendezvousToken: Data,
    offerHash: Data,
    candidate: TransportCandidate,
    offeredProfiles: [ProfileName],
    localKeys: PairKeyMaterial,
    remoteStaticPublic: Data,
    channel: RappMessageChannel
  ) {
    self.role = role
    self.pairIdentifier = pairIdentifier
    self.rendezvousToken = rendezvousToken
    self.offerHash = offerHash
    self.candidate = candidate
    self.offeredProfiles = offeredProfiles
    self.localKeys = localKeys
    self.remoteStaticPublic = remoteStaticPublic
    self.channel = channel
  }

  /// Send this peer's label and its exact parameter echo.
  internal mutating func sendHello(displayName: String, platform: String) throws -> Data {
    guard !localHelloSent else { throw PairingError.duplicateMessage }
    let hello = PairingHello(
      parameters: localParameters,
      displayName: displayName,
      platform: platform,
      requestedProfiles: role == .requester ? offeredProfiles : nil)
    let frame = try seal(.pairingHello, body: try body(of: hello))
    localHelloSent = true
    return frame
  }

  /// Verify the peer's hello: the parameter echo must match, and the presence
  /// of requested profiles must match the peer's role.
  internal mutating func receiveHello(_ frame: Data) throws -> PairingHello {
    guard peerHello == nil else { throw PairingError.duplicateMessage }
    let envelope = try open(frame)
    guard envelope.messageType == .pairingHello else { throw PairingError.unexpectedMessage }
    let hello: PairingHello
    do {
      hello = try PairingHello.from(body: envelope.body)
    } catch let error as MessageFieldError {
      throw PairingError.message(error)
    }
    guard hello.parameters == localParameters else { throw PairingError.parameterMismatch }
    switch role {
    case .requester:
      guard hello.requestedProfiles == nil else { throw PairingError.roleViolation }

    case .proxy:
      guard let requested = hello.requestedProfiles else { throw PairingError.roleViolation }
      // The offer names a set of profiles, so the requester's echo has to
      // name the same set. Requesters that list them in their own order are
      // making the same statement, and refusing those would end a pairing
      // over a sequence the protocol never gave meaning to.
      guard sortedByNameBytes(requested) == offeredProfiles else {
        throw PairingError.grantMismatch
      }
    }
    peerHello = hello
    return hello
  }

  /// Send the locally confirmed grant set, ordered so both peers encode the
  /// same bytes.
  internal mutating func sendConfirmation(grantedProfiles: [ProfileName]) throws -> Data {
    guard localHelloSent, peerHello != nil else { throw PairingError.helloIncomplete }
    guard !localConfirmationSent else { throw PairingError.duplicateMessage }
    try validateGrants(grantedProfiles, offered: offeredProfiles)
    let sorted = sortedByNameBytes(grantedProfiles)
    if peerConfirmationReceived, peerGrants != sorted { throw PairingError.grantMismatch }
    let frame = try seal(
      .pairingConfirm, body: try body(of: PairingConfirm(grantedProfiles: sorted)))
    localGrants = sorted
    localConfirmationSent = true
    return frame
  }

  /// Accept the peer's grant confirmation, which must equal the local one.
  internal mutating func receiveConfirmation(_ frame: Data) throws -> [ProfileName] {
    guard !peerConfirmationReceived else { throw PairingError.duplicateMessage }
    let envelope = try open(frame)
    guard envelope.messageType == .pairingConfirm else { throw PairingError.unexpectedMessage }
    let confirm: PairingConfirm
    do {
      confirm = try PairingConfirm.from(body: envelope.body)
    } catch let error as MessageFieldError {
      throw PairingError.message(error)
    }
    try validateGrants(confirm.grantedProfiles, offered: offeredProfiles)
    let sortedConfirm = sortedByNameBytes(confirm.grantedProfiles)
    if localConfirmationSent, localGrants != sortedConfirm { throw PairingError.grantMismatch }
    peerGrants = sortedConfirm
    peerConfirmationReceived = true
    return sortedConfirm
  }

  /// Build the only persistable record, after both hellos and both equal
  /// confirmations.
  internal func intoPairRecord(createdAtMilliseconds: UInt64) throws -> PairRecord {
    guard localHelloSent, peerHello != nil else { throw PairingError.helloIncomplete }
    guard localConfirmationSent, peerConfirmationReceived else {
      throw PairingError.confirmationIncomplete
    }
    guard localGrants == peerGrants else { throw PairingError.grantMismatch }
    let grantsHash: Data
    do {
      grantsHash = try RappHashes.grantsHash(profiles: localGrants.map(\.rawValue))
    } catch {
      throw PairingError.noise
    }
    do {
      return try PairRecord(
        pairIdentifier: pairIdentifier,
        rendezvousToken: rendezvousToken,
        role: role,
        localStaticPrivate: localKeys.privateKey,
        localStaticPublic: localKeys.publicKey,
        remoteStaticPublic: remoteStaticPublic,
        grantsHash: grantsHash,
        profiles: localGrants,
        transport: PairTransportBinding(
          profile: candidate.profile,
          candidateIdentifier: candidate.candidateIdentifier,
          parameters: candidate.parameters),
        createdAtMilliseconds: createdAtMilliseconds)
    } catch let error as PairRecordError {
      throw PairingError.pairRecord(error)
    }
  }

  private func body(of hello: PairingHello) throws -> [String: WireValue] {
    do {
      return try hello.body()
    } catch let error as MessageFieldError {
      throw PairingError.message(error)
    }
  }

  private func body(of confirm: PairingConfirm) throws -> [String: WireValue] {
    do {
      return try confirm.body()
    } catch let error as MessageFieldError {
      throw PairingError.message(error)
    }
  }

  private mutating func seal(
    _ messageType: MessageType, body: [String: WireValue]
  ) throws -> Data {
    do {
      return try channel.seal(messageType, body: body)
    } catch {
      throw PairingError.noise
    }
  }

  private mutating func open(_ frame: Data) throws -> Envelope {
    do {
      return try channel.open(frame)
    } catch let failure as RappOpenFailure {
      throw PairingError.open(failure)
    } catch {
      throw PairingError.open(.authenticatedProtocolViolation)
    }
  }
}
