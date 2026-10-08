// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension RappPairingBridge {
  /// Starts one CPace attempt over the connected candidate.
  ///
  /// The requester samples its scalar and prepares Y_A; the custodian keeps
  /// the random bytes until Y_A arrives.
  ///
  /// - Throws: ``RappBindingError/OfferExpired`` past the offer deadline,
  ///   ``RappBindingError/AttemptsExhausted`` once the custodian may admit no
  ///   further attempt, ``RappBindingError/WrongPhase`` outside the offer
  ///   phase, and ``RappBindingError/InvalidInput`` for an unknown candidate
  ///   or unusable random bytes.
  public func beginCpace(
    candidateId: String,
    randomBytes64: Data,
    nowMonotonicMs: UInt64
  ) throws {
    try locked {
      guard case .offer = phase else { throw RappBindingError.WrongPhase }
      guard deadline.isLive(nowMilliseconds: nowMonotonicMs) else {
        throw RappBindingError.OfferExpired
      }
      guard offer.transports.filter({ $0.candidateIdentifier == candidateId }).count == 1 else {
        throw RappBindingError.InvalidInput
      }
      candidateIdentifier = candidateId
      switch role {
      case .requester:
        do {
          phase = .requesterAwaitingStepTwo(
            try CpaceKc2Initiator(
              code: pairingCode, context: context,
              offerIdentifier: offer.offerIdentifier, randomBytes: randomBytes64))
        } catch {
          phase = .cancelled
          throw RappBindingError.InvalidInput
        }

      case .proxy:
        guard ledger.acceptsAnotherAttempt else {
          phase = .exhausted
          throw RappBindingError.AttemptsExhausted
        }
        guard randomBytes64.count == RappCpaceConstants.wideScalarSize else {
          throw RappBindingError.InvalidInput
        }
        phase = .custodianAwaitingStepOne(randomBytes: randomBytes64)
      }
    }
  }

  /// The next CPace message this role sends.
  ///
  /// The requester's step 3 hands off to Noise_XXpsk3: once it is written,
  /// the handshake is under way and the requester writes Noise message 1
  /// next.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` when this role has nothing to
  ///   send, and ``RappBindingError/OfferExpired`` past the deadline.
  public func writeCpaceFrame(nowMonotonicMs: UInt64) throws -> Data {
    try locked {
      switch phase {
      case .requesterAwaitingStepTwo(let initiator):
        guard deadline.isLive(nowMilliseconds: nowMonotonicMs) else {
          phase = .cancelled
          throw RappBindingError.OfferExpired
        }
        return initiator.stepOne

      case .requesterSendingStepThree(let stepThree, let presharedKey):
        try beginHandshake(presharedKey: presharedKey, nowMilliseconds: nowMonotonicMs)
        return stepThree

      case .custodianAwaitingStepThree(let responder):
        guard ledger.attemptIsLive(nowMilliseconds: nowMonotonicMs) else {
          throw failCustodianAttempt()
        }
        return responder.stepTwo

      default:
        throw RappBindingError.WrongPhase
      }
    }
  }

  /// Consumes one CPace message from the peer.
  ///
  /// - Throws: ``RappBindingError/ProtocolFailure`` when the message or a
  ///   confirmation tag does not verify, ``RappBindingError/AttemptsExhausted``
  ///   when that failure was the custodian's last attempt,
  ///   ``RappBindingError/OfferExpired`` past the deadline, and
  ///   ``RappBindingError/WrongPhase`` when no CPace message is expected.
  public func readCpaceFrame(bytes: Data, nowMonotonicMs: UInt64) throws {
    try locked {
      switch phase {
      case .requesterAwaitingStepTwo(let initiator):
        try confirmStepTwo(bytes, initiator: initiator, nowMilliseconds: nowMonotonicMs)

      case .custodianAwaitingStepOne(let randomBytes):
        try admitStepOne(bytes, randomBytes: randomBytes, nowMilliseconds: nowMonotonicMs)

      case .custodianAwaitingStepThree(let responder):
        guard ledger.attemptIsLive(nowMilliseconds: nowMonotonicMs) else {
          throw failCustodianAttempt()
        }
        let presharedKey: Data
        do {
          presharedKey = try responder.processStepThree(bytes)
        } catch {
          throw failCustodianAttempt()
        }
        ledger.consume()
        try beginHandshake(presharedKey: presharedKey, nowMilliseconds: nowMonotonicMs)

      default:
        throw RappBindingError.WrongPhase
      }
    }
  }

  /// Abandons the connected candidate after a disconnect or timeout.
  ///
  /// The custodian spends an admitted attempt and restores the offer while
  /// attempts and lifetime remain. A requester attempt, and any attempt past
  /// the CPace handoff, ends the ceremony.
  ///
  /// - Returns: whether the offer may serve another connection.
  public func candidateFailed(nowMonotonicMs: UInt64) -> Bool {
    locked {
      switch phase {
      case .finished, .cancelled, .exhausted:
        return false

      case .handshaking, .confirming, .requesterAwaitingStepTwo, .requesterSendingStepThree:
        phase = .cancelled
        return false

      case .offer, .custodianAwaitingStepOne, .custodianAwaitingStepThree:
        guard role == .proxy else {
          phase = .cancelled
          return false
        }
        ledger.failActiveAttempt()
        return restoreCustodianOffer(nowMilliseconds: nowMonotonicMs)
      }
    }
  }

  /// Verifies Y_B and T_B and prepares T_A.
  private func confirmStepTwo(
    _ stepTwo: Data, initiator: CpaceKc2Initiator, nowMilliseconds: UInt64
  ) throws {
    guard deadline.isLive(nowMilliseconds: nowMilliseconds) else {
      phase = .cancelled
      throw RappBindingError.OfferExpired
    }
    do {
      let result = try initiator.processStepTwo(stepTwo)
      phase = .requesterSendingStepThree(
        stepThree: result.stepThree, presharedKey: result.presharedKey)
    } catch {
      phase = .cancelled
      throw RappBindingError.ProtocolFailure
    }
  }

  /// Validates Y_A, reserves an attempt, then answers with Y_B and T_B.
  private func admitStepOne(_ stepOne: Data, randomBytes: Data, nowMilliseconds: UInt64) throws {
    let responder: CpaceKc2Responder
    do {
      responder = try CpaceKc2Responder(
        code: pairingCode, context: context, offerIdentifier: offer.offerIdentifier,
        stepOne: stepOne, randomBytes: randomBytes)
    } catch RappCpaceError.identityGenerator {
      phase = .cancelled
      throw RappBindingError.ProtocolFailure
    } catch {
      phase = .offer
      throw RappBindingError.ProtocolFailure
    }
    guard ledger.admit(nowMilliseconds: nowMilliseconds, offerExpiresAt: deadline.expiresAt)
    else {
      if ledger.isExhausted || !ledger.acceptsAnotherAttempt {
        phase = .exhausted
        throw RappBindingError.AttemptsExhausted
      }
      phase = .cancelled
      throw RappBindingError.OfferExpired
    }
    phase = .custodianAwaitingStepThree(responder)
  }

  /// Spends the active attempt and names the outcome.
  private func failCustodianAttempt() -> RappBindingError {
    ledger.failActiveAttempt()
    if ledger.isExhausted {
      phase = .exhausted
      return .AttemptsExhausted
    }
    phase = .offer
    return .ProtocolFailure
  }

  private func restoreCustodianOffer(nowMilliseconds: UInt64) -> Bool {
    if ledger.isExhausted {
      phase = .exhausted
      return false
    }
    guard ledger.acceptsAnotherAttempt, deadline.isLive(nowMilliseconds: nowMilliseconds) else {
      phase = .cancelled
      return false
    }
    phase = .offer
    return true
  }

  /// Hands the CPace key to Noise_XXpsk3 under the post-PAKE deadline.
  private func beginHandshake(presharedKey: Data, nowMilliseconds: UInt64) throws {
    do {
      phase = .handshaking(
        try PairingHandshake.begin(
          .init(
            role: role,
            offer: offer,
            candidateIdentifier: candidateIdentifier,
            localKeys: localKeys,
            presharedKey: presharedKey)),
        deadline: PairingPhaseDeadline.after(
          nowMilliseconds, PairingPhaseDeadline.handshakeMilliseconds))
    } catch {
      phase = .cancelled
      throw RappBindingError.ProtocolFailure
    }
  }
}
