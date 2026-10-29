// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The custodian's word on the card it holds and on its card reader (RAPP
/// v26.10.29 §7.1, §8.4): the body of `card.status`.
public struct RappCardStatus: Equatable, Sendable {
  /// An absent card carries this many zero bytes (§8.4 item 2).
  private static var absentFingerprint: Data { Data(count: RappCertificateFingerprint.byteCount) }

  /// The card the custodian holds.
  public let card: RappCardPresence
  /// Whether a contact card reader is connected to the custodian.
  public let reader: RappCardReader

  internal var wireBody: [String: WireValue] {
    let (present, fingerprint): (Bool, Data) =
      switch card {
      case .present(let named):
        (true, named.digest)

      case .absent:
        (false, Self.absentFingerprint)
      }
    return [
      "card_present": .boolean(present),
      "reader_attached": .boolean(reader == .attached),
      "certificate_fingerprint": .bytes(fingerprint),
    ]
  }

  /// The custodian holds `card`, and `reader` says whether a contact card
  /// reader is connected to it.
  public init(card: RappCardPresence, reader: RappCardReader) {
    self.card = card
    self.reader = reader
  }

  /// A received `card.status` body: every field present and no other, a
  /// present card naming a nonzero fingerprint and an absent one the zero
  /// fingerprint.
  internal static func from(wireBody: [String: WireValue]) throws -> Self {
    var body = wireBody
    let present = try takeBoolean(&body, "card_present")
    let readerAttached = try takeBoolean(&body, "reader_attached")
    let fingerprint = try takeBytes(&body, "certificate_fingerprint")
    guard body.isEmpty else { throw WireError.unknownField }
    let attachment: RappCardReader = readerAttached ? .attached : .absent
    if present, let named = RappCertificateFingerprint(received: fingerprint) {
      return Self(card: .present(named), reader: attachment)
    }
    guard !present, fingerprint == absentFingerprint else {
      throw MessageFieldError.invalidField("certificate_fingerprint")
    }
    return Self(card: .absent, reader: attachment)
  }
}
