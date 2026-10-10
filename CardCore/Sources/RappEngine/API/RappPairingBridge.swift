// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The pairing ceremony of RAPP v26.10.9, from a random offer to a stored
/// pairing.
///
/// The custodian creates the offer, shows the code and answers; the
/// requester reads the offer through the transport's bootstrap, types the
/// code and initiates both CPace and Noise_XXpsk3. One bridge runs one
/// ceremony.
/// A completed, cancelled or exhausted bridge is spent and refuses further
/// calls.
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
    case finished
    case cancelled
    case exhausted
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
  internal var ledger = CpaceAttemptLedger()
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
      self.deadline = try PairingOfferDeadline(
        offer: offer, startedAtMilliseconds: startedAtMonotonicMs)
      self.offerHash = try offer.offerHash()
    } catch {
      throw RappBindingError.InvalidInput
    }
    self.localKeys = PairKeyMaterial()
  }

  /// Builds the custodian's offer, served over `transportProfiles`
  /// (RAPP v26.10.9 §4.2).
  ///
  /// The offer identifier is fresh randomness the caller draws, never
  /// derived from the code; the requester learns it through the
  /// transport's bootstrap, which carries ``encodedOffer()``.
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

  /// Builds the requester's side from the offer the custodian served over
  /// the connection's transport (RAPP v26.10.9 §4.2 step 3).
  ///
  /// The offer must name the KC2 suite and carry an entry for
  /// `transportProfile`; anything else ends the flow before CPace, without
  /// fallback.
  ///
  /// - Throws: ``RappBindingError/InvalidInput`` for an offer that does not
  ///   decode, names no acceptable suite, or has no entry for the
  ///   transport.
  public static func bootstrapOffer(
    encodedOffer: Data,
    transportProfile: String,
    pairingCode: String,
    startedAtMonotonicMs: UInt64
  ) throws -> RappPairingBridge {
    let decoded: PairingOffer
    do {
      _ = try cpacePasswordString(pairingCode)
      decoded = try PairingOffer.decode(encodedOffer)
    } catch {
      throw RappBindingError.InvalidInput
    }
    guard decoded.entry(for: transportProfile) != nil else { throw RappBindingError.InvalidInput }
    return try RappPairingBridge(
      role: .requester, offer: decoded, pairingCode: pairingCode,
      startedAtMonotonicMs: startedAtMonotonicMs)
  }

  /// Names a ceremony failure in the public vocabulary.
  internal static func bindingError(_ error: PairingError) -> RappBindingError {
    switch error {
    case .offerExpired:
      .OfferExpired

    case .candidateNotUnique, .offer, .invalidGrantSet, .unsupportedProfile:
      .InvalidInput

    default:
      .ProtocolFailure
    }
  }

  internal func locked<Value>(_ body: () throws -> Value) rethrows -> Value {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  /// `encode_deterministic_cbor(pairing-offer)`: the bootstrap a custodian
  /// serves, on the BLE characteristic or as its first stream frame.
  public func encodedOffer() throws -> Data {
    do {
      return try locked { try offer.encoded() }
    } catch {
      throw RappBindingError.InvalidInput
    }
  }

  /// How long the offer lives, in milliseconds.
  public func offerTtlMs() -> UInt64 {
    locked { offer.offerLifetimeMilliseconds }
  }

  /// Whether three failed attempts destroyed the offer.
  public func attemptsExhausted() -> Bool {
    locked { ledger.isExhausted }
  }

  /// The transports the offer advertises.
  public func offerCandidates() -> [RappOfferCandidate] {
    locked {
      offer.transports.map { candidate in
        let bleParams = BleProfile.parameters(of: candidate)
        return RappOfferCandidate(
          profile: candidate.profile,
          candidateId: candidate.candidateIdentifier,
          streamEndpoints: StreamProfile.endpoints(of: candidate),
          bleServiceUUID: bleParams?.serviceUUID,
          blePsm: bleParams?.psm
        )
      }
    }
  }
}
