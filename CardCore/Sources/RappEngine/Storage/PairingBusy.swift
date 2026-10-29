// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The `pairing-busy` a custodian in pairing mode answers while it cannot
/// admit an attempt (RAPP v26.10.29 §3.3 item 6, §4.2 "PairingBusy Schema"
/// and "Busy Refusal").
///
/// It carries only the time until the custodian can admit an attempt,
/// between ``minimumRetryAfterMilliseconds`` and
/// ``maximumRetryAfterMilliseconds``, and nothing of the code or the offer.
internal struct PairingBusy: Equatable, Sendable {
  /// Least `retry_after_ms` a `pairing-busy` carries (§4.2).
  internal static let minimumRetryAfterMilliseconds: UInt64 = 1
  /// Greatest `retry_after_ms` a `pairing-busy` carries (§4.2).
  internal static let maximumRetryAfterMilliseconds: UInt64 = 5_000
  /// Field naming the wait; the `pairing-offer` schema has no field of that
  /// name, so its presence tells a busy answer from an offer.
  internal static let retryAfterField = "retry_after_ms"
  /// Fields of the `pairing-busy` schema.
  internal static let fields = [
    BootstrapAnswer.schemeField, BootstrapAnswer.versionField, retryAfterField,
  ]

  /// Milliseconds until the custodian can admit an attempt.
  internal let retryAfterMilliseconds: UInt64

  /// A busy answer asking the requester to wait `retryAfterMilliseconds`.
  ///
  /// - Throws: ``PairingOfferError/retryAfterOutOfRange(_:)`` outside the
  ///   schema's range.
  internal init(retryAfterMilliseconds: UInt64) throws {
    guard
      (Self.minimumRetryAfterMilliseconds...Self.maximumRetryAfterMilliseconds)
        .contains(retryAfterMilliseconds)
    else { throw PairingOfferError.retryAfterOutOfRange(retryAfterMilliseconds) }
    self.retryAfterMilliseconds = retryAfterMilliseconds
  }

  private init(heldWait: UInt64) {
    retryAfterMilliseconds = heldWait
  }

  /// A busy answer from its decoded top-level map.
  internal init(map: [String: WireValue]) throws {
    var remaining = map
    try BootstrapAnswer.takeHeader(&remaining, allowed: Self.fields)
    try self.init(retryAfterMilliseconds: try offerTakeUnsigned(&remaining, Self.retryAfterField))
  }

  /// The custodian's busy answer for a wait of `waitMilliseconds` until it
  /// can admit an attempt, held to the schema's range: a wait that has
  /// already passed asks for the least wait, a longer one for the greatest.
  internal static func untilAdmissible(_ waitMilliseconds: UInt64) -> Self {
    Self(
      heldWait: min(
        max(waitMilliseconds, minimumRetryAfterMilliseconds), maximumRetryAfterMilliseconds))
  }

  /// Decodes `encode_deterministic_cbor(pairing-busy)`.
  ///
  /// - Throws: ``PairingOfferError`` on malformed CBOR, a wrong scheme or
  ///   version, a missing or unknown field, or a wait out of range.
  internal static func decode(_ encoded: Data) throws -> Self {
    try Self(map: try BootstrapAnswer.decodeMap(encoded))
  }

  /// `encode_deterministic_cbor(pairing-busy)`.
  internal func encoded() throws -> Data {
    let map: [String: WireValue] = [
      BootstrapAnswer.schemeField: .text(offerSchemeName),
      BootstrapAnswer.versionField: wireVersionValue,
      Self.retryAfterField: .unsigned(retryAfterMilliseconds),
    ]
    return try WireValue.map(map).encoded()
  }
}
