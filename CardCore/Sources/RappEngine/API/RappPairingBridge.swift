// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The pairing ceremony of RAPP v26.10.29, from a random offer to a stored
/// pairing.
///
/// The custodian creates the offer, shows the code and answers; the
/// requester reads the offer through the transport's bootstrap, types the
/// code and initiates both CPace and Noise_XXpsk3. One bridge runs one
/// ceremony.
/// A completed or cancelled bridge is spent and refuses further calls.
public final class RappPairingBridge: @unchecked Sendable {
  /// Where the ceremony has reached.
  internal enum Phase {
    case offer
    case requesterAwaitingStepTwo(CpaceKc2Initiator)
    case requesterSendingStepThree(stepThree: Data, presharedKey: Data)
    case custodianAwaitingStepOne(randomBytes: Data)
    case custodianAwaitingStepThree(CpaceKc2Responder)
    case handshaking(PairingHandshake, deadline: UInt64)
    case confirming(PairingConfirmation, deadline: UInt64)
    /// The record is built and the storage exchange runs over the still
    /// open channel (RAPP v26.10.29 §4.3 item 4), under the confirmation
    /// deadline.
    case storage(PairingStorage, record: PairRecord, deadline: UInt64)
    case finished
    case cancelled
  }

  internal let lock = NSLock()
  internal let role: EndpointRole
  internal let offer: PairingOffer
  internal let pairingCode: String
  internal let offerHash: Data
  /// The CPace context of the connected candidate (§6.1.1).
  internal var context = Data()
  internal let deadline: PairingOfferDeadline
  internal let localKeys: PairKeyMaterial
  internal var attempt = CpaceAttemptSlot()
  /// The custodian's own 500 ms spacing of CPace starts (§3.3 item 6).
  internal let preAuthentication = RappPreAuthenticationLimiter()
  internal var candidateIdentifier = ""
  internal var phase = Phase.offer

  internal init(
    role: EndpointRole,
    offer: PairingOffer,
    pairingCode: String,
    startedAtMonotonicMs: UInt64
  ) throws {
    self.role = role
    self.offer = offer
    self.pairingCode = pairingCode
    do {
      self.deadline = try PairingOfferDeadline(startedAtMilliseconds: startedAtMonotonicMs)
      self.offerHash = try offer.offerHash()
    } catch {
      throw RappBindingError.InvalidInput
    }
    self.localKeys = PairKeyMaterial()
  }

  /// Builds the custodian's offer, served over `transportProfiles`
  /// (RAPP v26.10.29 §4.2).
  ///
  /// The offer identifier is fresh randomness the caller draws, never
  /// derived from the code; the requester learns it through the
  /// transport's bootstrap, which carries
  /// ``bootstrapBytes(nowMonotonicMs:)``.
  ///
  /// - Throws: ``RappBindingError/InvalidInput`` for a code that is not six
  ///   canonical characters, an identifier of the wrong size, an
  ///   unregistered transport profile, or profiles that break the offer
  ///   limits.
  public static func custodianOffer(
    pairingCode: String,
    offerId: Data,
    profiles: [String],
    transportProfiles: [String],
    startedAtMonotonicMs: UInt64
  ) throws -> RappPairingBridge {
    let created: PairingOffer
    do {
      _ = try cpacePasswordString(pairingCode)
      created = try PairingOffer.create(
        offerIdentifier: offerId, profiles: profiles, transportProfiles: transportProfiles)
    } catch {
      throw RappBindingError.InvalidInput
    }
    return try RappPairingBridge(
      role: .proxy, offer: created, pairingCode: pairingCode,
      startedAtMonotonicMs: startedAtMonotonicMs)
  }

  /// Builds the requester's side from the bootstrap answer the custodian
  /// served over the connection's transport (RAPP v26.10.29 §4.2, Bootstrap
  /// Read Flow item 3).
  ///
  /// An offer must name the KC2 suite and carry an entry for
  /// `transportProfile`; anything else ends the flow before CPace, without
  /// fallback.
  ///
  /// - Throws: ``RappBindingError/CustodianBusy`` when the answer is a
  ///   `pairing-busy`, and ``RappBindingError/InvalidInput`` for an answer
  ///   that decodes as neither a busy answer nor an offer listing the
  ///   transport.
  public static func bootstrapOffer(
    bootstrap: Data,
    transportProfile: String,
    pairingCode: String,
    startedAtMonotonicMs: UInt64
  ) throws -> RappPairingBridge {
    let answer: BootstrapAnswer
    do {
      _ = try cpacePasswordString(pairingCode)
      answer = try BootstrapAnswer.decode(bootstrap, transportProfile: transportProfile)
    } catch {
      throw RappBindingError.InvalidInput
    }
    switch answer {
    case .busy:
      throw RappBindingError.CustodianBusy

    case .offer(let decoded):
      return try RappPairingBridge(
        role: .requester, offer: decoded, pairingCode: pairingCode,
        startedAtMonotonicMs: startedAtMonotonicMs)
    }
  }

  /// Names a ceremony failure in the public vocabulary.
  internal static func bindingError(_ error: PairingError) -> RappBindingError {
    switch error {
    case .offerExpired:
      .OfferExpired

    case .candidateNotUnique, .offer, .invalidGrantSet, .unsupportedProfile:
      .InvalidInput

    case .storageUnconfirmed:
      .StorageUnconfirmed

    default:
      .ProtocolFailure
    }
  }

  internal func locked<Value>(_ body: () throws -> Value) rethrows -> Value {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  /// The custodian's bootstrap answer while its offer is live (RAPP
  /// v26.10.29 §4.2, Bootstrap Read Flow).
  ///
  /// It goes on the BLE characteristic or as the first stream frame:
  /// `encode_deterministic_cbor(pairing-offer)` while the custodian can
  /// admit an attempt, and `encode_deterministic_cbor(pairing-busy)` while
  /// it cannot, because an attempt holds the offer or the 500 ms spacing
  /// has not passed. After a busy answer the platform closes the connection.
  ///
  /// - Throws: ``RappBindingError/OfferExpired`` past the offer deadline,
  ///   and ``RappBindingError/WrongPhase`` for the requester or once the
  ///   offer is spent.
  public func bootstrapBytes(nowMonotonicMs: UInt64) throws -> Data {
    try locked {
      try requireLiveCustodianOffer(nowMilliseconds: nowMonotonicMs)
      let wait = admissionWaitMilliseconds(nowMilliseconds: nowMonotonicMs)
      guard case .offer = phase, wait == 0 else {
        return try busyAnswer(waitMilliseconds: wait)
      }
      do {
        return try offer.encoded()
      } catch {
        throw RappBindingError.ProtocolFailure
      }
    }
  }

  /// The `pairing-busy` the custodian sends on a pairing connection it
  /// refused while its offer is live, before closing the connection (RAPP
  /// v26.10.29 §4.2, "Busy Refusal").
  ///
  /// It carries the time until the custodian can admit an attempt: the
  /// larger of the time left on the active attempt, the time left of this
  /// bridge's spacing, and `spacingWaitMs`, held between 1 and 5000 ms. The
  /// platform calls it with `spacingWaitMs` from
  /// ``RappPreAuthenticationLimiter/waitMs(nowMonotonicMs:)`` in place of
  /// ``bootstrapBytes(nowMonotonicMs:)`` when that limiter refused a pairing
  /// connection, or for a pairing connection it cannot carry beside the one
  /// it serves; and with zero in place of CPace step 2 when
  /// ``beginCpace(candidateId:randomBytes64:nowMonotonicMs:)`` refused the
  /// connection's step 1 with ``RappBindingError/RateLimited`` or
  /// ``RappBindingError/WrongPhase``.
  ///
  /// - Throws: ``RappBindingError/OfferExpired`` past the offer deadline,
  ///   and ``RappBindingError/WrongPhase`` for the requester or once the
  ///   offer is spent.
  public func busyBytes(nowMonotonicMs: UInt64, spacingWaitMs: UInt64) throws -> Data {
    try locked {
      try requireLiveCustodianOffer(nowMilliseconds: nowMonotonicMs)
      return try busyAnswer(
        waitMilliseconds: max(
          admissionWaitMilliseconds(nowMilliseconds: nowMonotonicMs), spacingWaitMs))
    }
  }

  /// Whether a CPace step 1 arriving at `nowMonotonicMs` could be admitted.
  ///
  /// It can when the custodian's offer is live and idle, no attempt holds
  /// it, and the 500 ms spacing has passed. A BLE custodian refuses a step 1
  /// write it could not admit with ATT error Insufficient Resources (§4.2,
  /// "Busy Refusal" item 2).
  public func admitsAttempt(nowMonotonicMs: UInt64) -> Bool {
    locked {
      guard role == .proxy, case .offer = phase, attempt.acceptsAnotherAttempt,
        deadline.isLive(nowMilliseconds: nowMonotonicMs)
      else { return false }
      return admissionWaitMilliseconds(nowMilliseconds: nowMonotonicMs) == 0
    }
  }

  /// Checks that this custodian's offer can still admit attempts.
  private func requireLiveCustodianOffer(nowMilliseconds: UInt64) throws {
    guard role == .proxy else { throw RappBindingError.WrongPhase }
    switch phase {
    case .offer, .custodianAwaitingStepOne, .custodianAwaitingStepThree:
      break

    default:
      throw RappBindingError.WrongPhase
    }
    guard deadline.isLive(nowMilliseconds: nowMilliseconds) else {
      throw RappBindingError.OfferExpired
    }
  }

  /// Milliseconds until the custodian can admit an attempt: the larger of
  /// the time left on the active attempt's deadline and the time left of
  /// the 500 ms spacing (§3.3 item 6).
  private func admissionWaitMilliseconds(nowMilliseconds: UInt64) -> UInt64 {
    max(
      attempt.activeAttemptWaitMilliseconds(nowMilliseconds: nowMilliseconds),
      preAuthentication.waitMs(nowMonotonicMs: nowMilliseconds))
  }

  /// The encoded `pairing-busy` for a wait of `waitMilliseconds`.
  private func busyAnswer(waitMilliseconds: UInt64) throws -> Data {
    do {
      return try PairingBusy.untilAdmissible(waitMilliseconds).encoded()
    } catch {
      throw RappBindingError.ProtocolFailure
    }
  }

  /// The offer a requester read, while CPace has not begun on it.
  internal func requesterOfferAwaitingCpace() -> PairingOffer? {
    locked {
      guard role == .requester, case .offer = phase else { return nil }
      return offer
    }
  }

  /// The transports the offer advertises.
  public func offerCandidates() -> [RappOfferCandidate] {
    locked {
      offer.transports.map { candidate in
        RappOfferCandidate(profile: candidate.profile, candidateId: candidate.candidateIdentifier)
      }
    }
  }
}
