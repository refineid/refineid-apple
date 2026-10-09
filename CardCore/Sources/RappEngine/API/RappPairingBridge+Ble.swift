// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension RappPairingBridge {
  /// Builds the custodian's BLE offer (RAPP v26.10.1 §4.2).
  ///
  /// The offer identifier is fresh randomness the caller draws, never
  /// derived from the code; the requester learns it by reading the
  /// bootstrap characteristic, which carries ``encodedOffer()``.
  ///
  /// - Throws: ``RappBindingError/InvalidInput`` for a code that is not six
  ///   canonical characters, an identifier of the wrong size, or profiles
  ///   that break the offer limits.
  public static func bleOffer(
    pairingCode: String,
    offerId: Data,
    profiles: [String],
    startedAtMonotonicMs: UInt64
  ) throws -> RappPairingBridge {
    let offer: PairingOffer
    do {
      _ = try cpacePasswordString(pairingCode)
      offer = try PairingOffer(
        offerIdentifier: offerId,
        suites: [RappCpaceConstants.kc2Suite],
        profiles: profiles,
        transports: [RappBleGattProfile.candidate],
        offerLifetimeMilliseconds: RappBleGattProfile.offerLifetimeMilliseconds)
    } catch {
      throw RappBindingError.InvalidInput
    }
    return try RappPairingBridge(
      role: .proxy, offer: offer, pairingCode: pairingCode,
      startedAtMonotonicMs: startedAtMonotonicMs)
  }

  /// Builds the requester's side from the offer read off the bootstrap
  /// characteristic.
  ///
  /// The offer must name the KC2 suite and advertise the BLE candidate;
  /// anything else ends the flow before CPace, without fallback.
  ///
  /// - Throws: ``RappBindingError/InvalidInput`` for an offer that does not
  ///   decode, names no acceptable suite, or carries no BLE candidate.
  public static func bootstrapOffer(
    encodedOffer: Data,
    pairingCode: String,
    startedAtMonotonicMs: UInt64
  ) throws -> RappPairingBridge {
    let offer: PairingOffer
    do {
      _ = try cpacePasswordString(pairingCode)
      offer = try PairingOffer.decode(encodedOffer)
    } catch {
      throw RappBindingError.InvalidInput
    }
    guard
      offer.transports.contains(where: { candidate in
        candidate.profile == RappBleGattProfile.name
          && candidate.candidateIdentifier == RappBleGattProfile.candidateId
      })
    else { throw RappBindingError.InvalidInput }
    return try RappPairingBridge(
      role: .requester, offer: offer, pairingCode: pairingCode,
      startedAtMonotonicMs: startedAtMonotonicMs)
  }

  /// `encode_deterministic_cbor(pairing-offer)`, as the bootstrap
  /// characteristic serves it.
  public func encodedOffer() throws -> Data {
    do {
      return try locked { try offer.encoded() }
    } catch {
      throw RappBindingError.InvalidInput
    }
  }
}
