// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// Scheme name carried inside the encoded offer.
internal let offerSchemeName = "rapp"

/// Validated pairing offer (RAPP v26.10.9 §4.2).
///
/// The offer carries no secret: the pre-shared key comes from CPace, so the
/// offer is public and its hash binds the context, the prologue and the
/// parameter echo.
internal struct PairingOffer: Sendable {
  private static let fields = [
    "scheme", "version", "offer_id", "suites", "profiles", "transports", "offer_ttl_ms",
  ]

  internal let offerIdentifier: Data
  internal let suites: [String]
  internal let profiles: [String]
  internal let transports: [TransportCandidate]
  internal let offerLifetimeMilliseconds: UInt64

  internal init(
    offerIdentifier: Data,
    suites: [String],
    profiles: [String],
    transports: [TransportCandidate],
    offerLifetimeMilliseconds: UInt64
  ) throws {
    self.offerIdentifier = offerIdentifier
    self.suites = suites
    self.profiles = profiles
    self.transports = transports
    self.offerLifetimeMilliseconds = offerLifetimeMilliseconds
    try validate()
  }

  /// A fresh offer naming `transportProfiles`, each with its registered
  /// entry (RAPP v26.10.9 §4.2).
  ///
  /// The identifier is randomness the caller draws; it is never derived
  /// from the pairing code.
  internal static func create(
    offerIdentifier: Data, profiles: [String], transportProfiles: [String]
  ) throws -> Self {
    let entries = try transportProfiles.map { profile in
      guard let entry = TransportRegistry.entry(for: profile) else {
        throw PairingOfferError.invalidTransport
      }
      return entry
    }
    return try Self(
      offerIdentifier: offerIdentifier,
      suites: [RappCpaceConstants.kc2Suite],
      profiles: profiles,
      transports: entries.sorted { first, second in
        Data(first.profile.utf8).lexicographicallyPrecedes(Data(second.profile.utf8))
      },
      offerLifetimeMilliseconds: OfferLimit.offerLifetimeMilliseconds)
  }

  /// Decodes `encode_deterministic_cbor(pairing-offer)`.
  internal static func decode(_ encoded: Data) throws -> Self {
    guard encoded.count <= OfferLimit.encodedOfferSize else { throw PairingOfferError.oversized }
    let value: WireValue
    do {
      value = try decodeDeterministicCbor(encoded)
    } catch let error as WireError {
      throw PairingOfferError.wire(error)
    }
    guard case .map(var map) = value else { throw PairingOfferError.wrongType }
    guard map.keys.allSatisfy(fields.contains) else { throw PairingOfferError.unknownField }
    guard try offerTakeText(&map, "scheme") == offerSchemeName else {
      throw PairingOfferError.wrongScheme
    }
    guard case .array(let version) = try offerTakeValue(&map, "version"),
      WireValue.array(version) == wireVersionValue
    else { throw PairingOfferError.unsupportedVersion }
    let decodedOfferIdentifier = try offerTakeBytes(&map, "offer_id")
    let decodedSuites = try offerTakeTextArray(&map, "suites")
    let decodedProfiles = try offerTakeTextArray(&map, "profiles")
    let decodedTransports = try offerTakeArray(&map, "transports").map(candidateFrom)
    let lifetime = try offerTakeUnsigned(&map, "offer_ttl_ms")
    return try Self(
      offerIdentifier: decodedOfferIdentifier,
      suites: decodedSuites,
      profiles: decodedProfiles,
      transports: decodedTransports,
      offerLifetimeMilliseconds: lifetime)
  }

  private static func candidateValue(_ candidate: TransportCandidate) -> WireValue {
    .map([
      "profile": .text(candidate.profile),
      "candidate_id": .text(candidate.candidateIdentifier),
      "parameters": .map(candidate.parameters),
    ])
  }

  private static func candidateFrom(_ value: WireValue) throws -> TransportCandidate {
    guard case .map(var map) = value else { throw PairingOfferError.wrongType }
    let expected = ["profile", "candidate_id", "parameters"]
    guard map.keys.allSatisfy(expected.contains) else { throw PairingOfferError.unknownField }
    let profile = try offerTakeText(&map, "profile")
    let candidateIdentifier = try offerTakeText(&map, "candidate_id")
    guard case .map(let parameters) = try offerTakeValue(&map, "parameters") else {
      throw PairingOfferError.wrongType
    }
    return TransportCandidate(
      profile: profile, candidateIdentifier: candidateIdentifier, parameters: parameters)
  }

  private func validate() throws {
    guard offerIdentifier.count == OfferLimit.offerIdentifierSize else {
      throw PairingOfferError.wrongLength("offer_id")
    }
    guard !suites.isEmpty, !profiles.isEmpty, !transports.isEmpty else {
      throw PairingOfferError.emptyRequiredArray
    }
    guard suites.contains(RappCpaceConstants.kc2Suite) else {
      throw PairingOfferError.mandatorySuiteMissing
    }
    guard transports.count <= OfferLimit.transportCandidates else {
      throw PairingOfferError.tooManyTransports
    }
    guard offerLifetimeMilliseconds == OfferLimit.offerLifetimeMilliseconds else {
      throw PairingOfferError.invalidLifetime
    }
    let names = transports.map { Data($0.profile.utf8) }
    guard zip(names, names.dropFirst()).allSatisfy({ $0.lexicographicallyPrecedes($1) }),
      transports.allSatisfy({ TransportRegistry.entry(for: $0.profile) == $0 })
    else {
      throw PairingOfferError.invalidTransport
    }
  }

  /// The entry naming `profile`, if the offer is served over it.
  internal func entry(for profile: String) -> TransportCandidate? {
    transports.first { $0.profile == profile }
  }

  /// `encode_deterministic_cbor(pairing-offer)`.
  internal func encoded() throws -> Data {
    let map: [String: WireValue] = [
      "scheme": .text(offerSchemeName),
      "version": wireVersionValue,
      "offer_id": .bytes(offerIdentifier),
      "suites": .array(suites.map(WireValue.text)),
      "profiles": .array(profiles.map(WireValue.text)),
      "transports": .array(transports.map(Self.candidateValue)),
      "offer_ttl_ms": .unsigned(offerLifetimeMilliseconds),
    ]
    let bytes = try WireValue.map(map).encoded()
    guard bytes.count <= OfferLimit.encodedOfferSize else { throw PairingOfferError.oversized }
    return bytes
  }

  /// `SHA-256(encode_deterministic_cbor(pairing-offer))`.
  internal func offerHash() throws -> Data {
    Data(SHA256.hash(data: try encoded()))
  }
}
