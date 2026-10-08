// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The pairing ceremony of RAPP v26.10.1, from a code-derived offer to a
/// stored pairing.
///
/// The custodian shows the code and answers; the requester types the code
/// and initiates both CPace and Noise_XXpsk3. One bridge runs one ceremony.
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
  internal let context: Data
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
      self.context = try cpaceKc2Context(offerHash: offerHash)
    } catch {
      throw RappBindingError.InvalidInput
    }
    self.localKeys = PairKeyMaterial()
  }

  /// Builds the offer both peers derive from one pairing code.
  ///
  /// The custodian calls this with the code it shows, the requester with the
  /// code the user typed. Both must pass the same profiles, transports and
  /// lifetime, because the offer hash binds them.
  ///
  /// - Throws: ``RappBindingError/InvalidInput`` for a code that is not six
  ///   canonical characters or an offer that breaks the specification's
  ///   limits.
  public static func codeOffer(  // swiftlint:disable:this function_parameter_count
    role: RappEndpointRole,
    pairingCode: String,
    profiles: [String],
    transports: [RappTransportCandidate],
    offerTtlMs: UInt64,
    startedAtMonotonicMs: UInt64
  ) throws -> RappPairingBridge {
    let candidates = try transports.map { candidate in
      TransportCandidate(
        profile: candidate.profile,
        candidateIdentifier: candidate.candidateId,
        parameters: try decodedParameters(candidate.parametersCbor))
    }
    let derived: PairingOffer
    do {
      derived = try PairingOffer.fromCode(
        pairingCode, profiles: profiles, transports: candidates,
        offerLifetimeMilliseconds: offerTtlMs)
    } catch {
      throw RappBindingError.InvalidInput
    }
    return try RappPairingBridge(
      role: role.engineRole, offer: derived, pairingCode: pairingCode,
      startedAtMonotonicMs: startedAtMonotonicMs)
  }

  /// Decodes a candidate's public parameters.
  private static func decodedParameters(_ bytes: Data) throws -> [String: WireValue] {
    guard !bytes.isEmpty else { return [:] }
    guard case .map(let parameters)? = try? decodeDeterministicCbor(bytes) else {
      throw RappBindingError.InvalidInput
    }
    return parameters
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
