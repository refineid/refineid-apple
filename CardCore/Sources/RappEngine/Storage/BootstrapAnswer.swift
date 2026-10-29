// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What a requester reads from a custodian in pairing mode (RAPP v26.10.29
/// §4.2, Bootstrap Read Flow item 3): the offer while the custodian can
/// admit an attempt, and `pairing-busy` while it cannot.
internal enum BootstrapAnswer: Sendable {
  /// The custodian cannot admit an attempt now.
  case busy(PairingBusy)
  /// The custodian can admit an attempt: its offer, listing the transport
  /// it arrived over.
  case offer(PairingOffer)

  /// The scheme field both bootstrap answers carry.
  internal static let schemeField = "scheme"
  /// The version field both bootstrap answers carry.
  internal static let versionField = "version"

  /// Decodes the bootstrap bytes received over `transportProfile`.
  ///
  /// A map carrying `retry_after_ms` is a `pairing-busy`; any other is a
  /// `pairing-offer`, which must list `transportProfile`.
  ///
  /// - Throws: ``PairingOfferError`` when the answer decodes as neither.
  internal static func decode(_ encoded: Data, transportProfile: String) throws -> Self {
    let map = try decodeMap(encoded)
    if map[PairingBusy.retryAfterField] != nil {
      return .busy(try PairingBusy(map: map))
    }
    let offer = try PairingOffer(map: map)
    guard offer.entry(for: transportProfile) != nil else {
      throw PairingOfferError.transportNotOffered
    }
    return .offer(offer)
  }

  /// Decodes bounded bootstrap bytes into their top-level map.
  internal static func decodeMap(_ encoded: Data) throws -> [String: WireValue] {
    guard encoded.count <= OfferLimit.encodedOfferSize else { throw PairingOfferError.oversized }
    let value: WireValue
    do {
      value = try decodeDeterministicCbor(encoded)
    } catch let error as WireError {
      throw PairingOfferError.wire(error)
    }
    guard case .map(let map) = value else { throw PairingOfferError.wrongType }
    return map
  }

  /// Checks that `map` has no field outside `allowed`, and takes and checks
  /// the scheme and version both bootstrap answers carry.
  internal static func takeHeader(_ map: inout [String: WireValue], allowed: [String]) throws {
    guard map.keys.allSatisfy(allowed.contains) else { throw PairingOfferError.unknownField }
    guard try offerTakeText(&map, schemeField) == offerSchemeName else {
      throw PairingOfferError.wrongScheme
    }
    guard try offerTakeValue(&map, versionField) == wireVersionValue else {
      throw PairingOfferError.unsupportedVersion
    }
  }
}
