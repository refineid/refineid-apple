// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension RappPairingBridge {
  /// Starts the CPace exchange over one advertised transport using the pairing code.
  ///
  /// - Throws: ``RappBindingError/OfferExpired`` past the deadline,
  ///   ``RappBindingError/WrongPhase`` outside the offer phase, and
  ///   ``RappBindingError/InvalidInput`` for an invalid code or scalar failure.
  public func beginCpace(
    candidateId: String,
    pairingCode: String,
    randomBytes64: Data,
    nowMonotonicMs: UInt64
  ) throws {
    try locked {
      guard case .offer = phase else { throw RappBindingError.WrongPhase }
      guard deadline.isLive(nowMilliseconds: nowMonotonicMs) else {
        throw RappBindingError.OfferExpired
      }
      do {
        let isInitiator = role == .requester
        let cpace = try RappCpaceState(
          isInitiator: isInitiator,
          pairingCode: pairingCode,
          offerId: offer.offerIdentifier,
          randomBytes64: randomBytes64
        )
        phase = .cpace(cpace: cpace, offer: offer, candidateId: candidateId)
      } catch {
        throw RappBindingError.InvalidInput
      }
    }
  }

  /// Produces the local CPace public point frame to send to the peer.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` outside the CPace phase, and
  ///   ``RappBindingError/OfferExpired`` past the deadline.
  public func writeCpaceFrame(nowMonotonicMs: UInt64) throws -> Data {
    try locked {
      guard case .cpace(let cpace, _, _) = phase else { throw RappBindingError.WrongPhase }
      guard deadline.isLive(nowMilliseconds: nowMonotonicMs) else {
        throw RappBindingError.OfferExpired
      }
      do {
        return try cpace.writeMessage()
      } catch {
        throw RappBindingError.ProtocolFailure
      }
    }
  }

  /// Consumes the peer's CPace frame, derives the shared pairing secret, and begins Noise XXpsk3.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` outside the CPace phase,
  ///   ``RappBindingError/OfferExpired`` past the deadline, and
  ///   ``RappBindingError/ProtocolFailure`` on invalid point or handshake initiation failure.
  public func readCpaceFrame(bytes: Data, nowMonotonicMs: UInt64) throws {
    try locked {
      try processCpaceFrame(bytes: bytes, nowMonotonicMs: nowMonotonicMs)
    }
  }

  private func processCpaceFrame(bytes: Data, nowMonotonicMs: UInt64) throws {
    guard case .cpace(let cpace, let offer, let candidateId) = phase else {
      throw RappBindingError.WrongPhase
    }
    guard deadline.isLive(nowMilliseconds: nowMonotonicMs) else {
      throw RappBindingError.OfferExpired
    }
    let secret: Data
    do {
      secret = try cpace.readMessage(bytes)
    } catch {
      phase = .offer
      throw RappBindingError.ProtocolFailure
    }
    try startHandshakeWithSecret(
      secret: secret,
      offer: offer,
      candidateId: candidateId,
      nowMonotonicMs: nowMonotonicMs
    )
  }

  private func startHandshakeWithSecret(
    secret: Data,
    offer: PairingOffer,
    candidateId: String,
    nowMonotonicMs: UInt64
  ) throws {
    do {
      let updatedOffer = try offer.withPairingSecret(secret)
      phase = .handshaking(
        try PairingHandshake.begin(
          .init(
            role: role,
            offer: updatedOffer,
            candidateIdentifier: candidateId,
            localKeys: localKeys,
            deadline: deadline,
            nowMilliseconds: nowMonotonicMs
          )
        )
      )
    } catch let failure as PairingAttemptFailure {
      phase = .offer
      throw Self.bindingError(failure.error)
    } catch {
      phase = .offer
      throw RappBindingError.ProtocolFailure
    }
  }
}
