// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// An in-progress pairing handshake over exactly one transport candidate.
internal struct PairingHandshake {
  // MARK: Nested Types

  /// Everything one handshake attempt starts from.
  internal struct Attempt {
    internal let role: EndpointRole
    internal let offer: PairingOffer
    internal let candidateIdentifier: String
    internal let localKeys: PairKeyMaterial
    /// The 32-byte pre-shared key CPace established for this attempt.
    internal let presharedKey: Data
  }

  private let role: EndpointRole

  private let offer: PairingOffer

  private let offerHash: Data

  private let candidate: TransportCandidate

  private let offeredProfiles: [ProfileName]

  private let localKeys: PairKeyMaterial

  private var noise: NoiseHandshakeState

  internal var isComplete: Bool { noise.isComplete }

  /// Begin one attempt against one named candidate of a live offer.
  internal static func begin(_ attempt: Attempt) throws -> Self {
    func fail(_ error: PairingError) -> PairingAttemptFailure {
      PairingAttemptFailure(error: error, offer: attempt.offer)
    }
    let matches = attempt.offer.transports.filter { candidate in
      candidate.candidateIdentifier == attempt.candidateIdentifier
    }
    guard matches.count == 1, let selectedCandidate = matches.first else {
      throw fail(.candidateNotUnique)
    }
    let decodedOfferedProfiles: [ProfileName]
    let decodedOfferHash: Data
    do {
      decodedOfferedProfiles = try parseOfferedProfiles(attempt.offer.profiles)
      decodedOfferHash = try attempt.offer.offerHash()
    } catch let error as PairingError {
      throw fail(error)
    } catch let error as PairingOfferError {
      throw fail(.offer(error))
    }
    do {
      let handshakeState = try NoiseHandshakeState(
        pattern: .xxPsk3,
        suiteName: RappNoise.pairingSuite,
        prologue: try RappNoise.pairingPrologue(
          offerHash: decodedOfferHash, transportProfile: selectedCandidate.profile),
        isInitiator: attempt.role == .requester,
        localStaticPrivate: attempt.localKeys.privateKey,
        remoteStaticPublic: nil,
        presharedKey: attempt.presharedKey,
        fixedEphemeralPrivate: Curve25519.KeyAgreement.PrivateKey().rawRepresentation)
      return Self(
        role: attempt.role, offer: attempt.offer, offerHash: decodedOfferHash,
        candidate: selectedCandidate, offeredProfiles: decodedOfferedProfiles,
        localKeys: attempt.localKeys, noise: handshakeState)
    } catch {
      throw fail(.noise)
    }
  }

  /// The next handshake frame for this role.
  ///
  /// Handshake payloads stay empty.
  internal mutating func writeMessage() throws -> Data {
    do {
      return try noise.writeMessage()
    } catch {
      throw PairingError.noise
    }
  }

  /// Consume one handshake frame and refuse any payload bytes it carries.
  internal mutating func readMessage(_ frame: Data) throws {
    let payload: Data
    do {
      payload = try noise.readMessage(frame)
    } catch {
      throw PairingError.noise
    }
    guard payload.isEmpty else { throw PairingError.noise }
  }

  /// End this attempt and hand the still-live offer back for another candidate.
  ///
  /// Consuming: one attempt can never be resumed after it is abandoned, so two
  /// attempts cannot share the offer's one-use secret.
  internal consuming func abort() -> PairingOffer { offer }

  /// Complete the handshake and enter authenticated confirmation, consuming
  /// the offer's one-use secret.
  internal consuming func intoConfirmation() throws -> PairingConfirmation {
    guard noise.isComplete else {
      throw PairingAttemptFailure(error: .noise, offer: offer)
    }
    guard let remoteStatic = noise.authenticatedRemoteStatic else {
      throw PairingAttemptFailure(error: .missingPairIdentifier, offer: offer)
    }
    let transcript = noise.handshakeHash
    let split: (send: NoiseCipherState, receive: NoiseCipherState)
    do {
      split = try noise.split()
    } catch {
      throw PairingAttemptFailure(error: .noise, offer: offer)
    }
    let sessionIdentifier = RappNoise.sessionIdentifier(handshakeHash: transcript)
    return PairingConfirmation(
      role: role,
      pairIdentifier: RappNoise.pairIdentifier(handshakeHash: transcript),
      rendezvousToken: RappNoise.rendezvousToken(handshakeHash: transcript),
      offerHash: offerHash,
      candidate: candidate,
      offeredProfiles: offeredProfiles,
      localKeys: localKeys,
      remoteStaticPublic: remoteStatic,
      channel: RappMessageChannel(
        channel: RappSecureChannel(send: split.send, receive: split.receive),
        sessionIdentifier: sessionIdentifier))
  }
}
