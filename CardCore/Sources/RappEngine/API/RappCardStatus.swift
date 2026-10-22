// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The custodian's word on whether it can serve a card now, and which
/// (RAPP v26.10.21 §8.4): the body of `card.status`.
public enum RappCardStatus: Equatable, Sendable {
  /// No card can answer now.
  case absent
  /// A card can answer now; the fingerprint of its authentication
  /// certificate.
  case present(RappCertificateFingerprint)

  /// An absent card carries this many zero bytes, so the message has one
  /// size whatever it says.
  private static var absentFingerprint: Data { Data(count: RappCertificateFingerprint.byteCount) }

  internal var wireBody: [String: WireValue] {
    switch self {
    case .present(let fingerprint):
      ["card_present": .boolean(true), "certificate_fingerprint": .bytes(fingerprint.digest)]

    case .absent:
      [
        "card_present": .boolean(false),
        "certificate_fingerprint": .bytes(Self.absentFingerprint),
      ]
    }
  }

  /// A received `card.status` body: a present card names a nonzero
  /// fingerprint, an absent one the zero fingerprint.
  internal static func from(wireBody: [String: WireValue]) throws -> Self {
    var body = wireBody
    let present = try takeBoolean(&body, "card_present")
    let fingerprint = try takeBytes(&body, "certificate_fingerprint")
    guard body.isEmpty else { throw MessageFieldError.invalidField("certificate_fingerprint") }
    if present, let named = RappCertificateFingerprint(received: fingerprint) {
      return .present(named)
    }
    guard !present, fingerprint == absentFingerprint else {
      throw MessageFieldError.invalidField("certificate_fingerprint")
    }
    return .absent
  }
}
