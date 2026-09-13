// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// Scheme prefix carried by the scanned URI.
internal let offerUriPrefix = "rapp:"

/// Scheme name repeated inside the encoded offer.
internal let offerSchemeName = "rapp"

/// Validated high-entropy pairing offer.
///
/// The bearer secret is carried only to reach the QR payload and the pairing
/// handshake; it is deliberately absent from the hashed form.
internal struct PairingOffer: Sendable {
  internal let offerIdentifier: Data
  internal let pairingSecret: Data
  internal let suites: [String]
  internal let profiles: [String]
  internal let transports: [TransportCandidate]
  internal let offerLifetimeMilliseconds: UInt64

  internal init(
    offerIdentifier: Data,
    pairingSecret: Data,
    suites: [String],
    profiles: [String],
    transports: [TransportCandidate],
    offerLifetimeMilliseconds: UInt64
  ) throws {
    self.offerIdentifier = offerIdentifier
    self.pairingSecret = pairingSecret
    self.suites = suites
    self.profiles = profiles
    self.transports = transports
    self.offerLifetimeMilliseconds = offerLifetimeMilliseconds
    try validate()
  }

  /// A scanned QR URI, decoded and validated.
  internal static func from(uri: String) throws -> Self {
    guard uri.hasPrefix(offerUriPrefix) else { throw PairingOfferError.wrongScheme }
    let payload = String(uri.dropFirst(offerUriPrefix.count))
    let decoded = try base64UrlDecode(payload)
    guard decoded.count <= OfferLimit.encodedOfferSize else { throw PairingOfferError.oversized }
    let value: WireValue
    do {
      value = try decodeDeterministicCbor(decoded)
    } catch let error as WireError {
      throw PairingOfferError.wire(error)
    }
    guard case .map(var map) = value else { throw PairingOfferError.wrongType }
    let expected = [
      "scheme", "version", "offer_id", "pairing_secret", "suites", "profiles", "transports",
      "offer_ttl_ms",
    ]
    guard map.keys.allSatisfy(expected.contains) else { throw PairingOfferError.unknownField }
    guard try offerTakeText(&map, "scheme") == offerSchemeName else {
      throw PairingOfferError.wrongScheme
    }
    guard
      try offerTakeArray(&map, "version") == [
        .unsigned(RappNoise.wireVersion.major), .unsigned(RappNoise.wireVersion.minor),
        .unsigned(RappNoise.wireVersion.patch),
      ]
    else { throw PairingOfferError.unsupportedVersion }
    let decodedOfferIdentifier = try offerTakeBytes(&map, "offer_id")
    guard decodedOfferIdentifier.count == OfferLimit.offerIdentifierSize else {
      throw PairingOfferError.wrongLength("offer_id")
    }
    let secret = try offerTakeBytes(&map, "pairing_secret")
    guard secret.count == OfferLimit.pairingSecretSize else {
      throw PairingOfferError.wrongLength("pairing_secret")
    }
    let decodedSuites = try offerTakeTextArray(&map, "suites")
    let decodedProfiles = try offerTakeTextArray(&map, "profiles")
    let decodedTransports = try offerTakeArray(&map, "transports").map(candidateFrom)
    let lifetime = try offerTakeUnsigned(&map, "offer_ttl_ms")
    return try Self(
      offerIdentifier: decodedOfferIdentifier,
      pairingSecret: secret,
      suites: decodedSuites,
      profiles: decodedProfiles,
      transports: decodedTransports,
      offerLifetimeMilliseconds: lifetime
    )
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
    guard let parameters = map.removeValue(forKey: "parameters") else {
      throw PairingOfferError.missingField("parameters")
    }
    guard case .map(let entries) = parameters else { throw PairingOfferError.wrongType }
    return TransportCandidate(
      profile: profile, candidateIdentifier: candidateIdentifier, parameters: entries)
  }

  private func validate() throws {
    guard !suites.isEmpty, !profiles.isEmpty, !transports.isEmpty else {
      throw PairingOfferError.emptyRequiredArray
    }
    guard suites.contains(mandatoryPairingSuite) else {
      throw PairingOfferError.mandatorySuiteMissing
    }
    guard transports.count <= OfferLimit.transportCandidates else {
      throw PairingOfferError.tooManyTransports
    }
    guard offerLifetimeMilliseconds > 0,
      offerLifetimeMilliseconds <= OfferLimit.offerLifetimeMaximumMilliseconds
    else {
      throw PairingOfferError.invalidLifetime
    }
    guard
      !transports.contains(where: { $0.profile.isEmpty || $0.candidateIdentifier.isEmpty })
    else {
      throw PairingOfferError.invalidTransport
    }
  }

  /// The offer as a deterministic map, with the bearer secret optional.
  private func asMap(includingSecret: Bool) -> [String: WireValue] {
    var map: [String: WireValue] = [
      "scheme": .text(offerSchemeName),
      "version": .array([
        .unsigned(RappNoise.wireVersion.major), .unsigned(RappNoise.wireVersion.minor),
        .unsigned(RappNoise.wireVersion.patch),
      ]),
      "offer_id": .bytes(offerIdentifier),
      "suites": .array(suites.map(WireValue.text)),
      "profiles": .array(profiles.map(WireValue.text)),
      "transports": .array(transports.map(Self.candidateValue)),
      "offer_ttl_ms": .unsigned(offerLifetimeMilliseconds),
    ]
    if includingSecret {
      map["pairing_secret"] = .bytes(pairingSecret)
    }
    return map
  }

  /// Hash of the deterministic offer with the bearer secret removed.
  internal func offerHash() throws -> Data {
    let encoded = try WireValue.map(asMap(includingSecret: false)).encoded()
    return Data(SHA256.hash(data: encoded))
  }

  /// The complete secret-bearing QR payload.
  internal func uri() throws -> String {
    try validate()
    let encoded = try WireValue.map(asMap(includingSecret: true)).encoded()
    guard encoded.count <= OfferLimit.encodedOfferSize else { throw PairingOfferError.oversized }
    return offerUriPrefix + base64UrlEncode(encoded)
  }
}
