// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Monotonic lifetime of one in-memory pairing offer.
///
/// The clock origin comes from the platform, so the same logic serves every
/// operating system. It is meaningful only inside the process that created or
/// scanned the offer and is never serialized.
internal struct PairingOfferDeadline: Equatable {
  private let startedAtMilliseconds: UInt64
  private let expiresAtMilliseconds: UInt64

  /// The monotonic instant the offer stops being live.
  internal var expiresAt: UInt64 { expiresAtMilliseconds }

  internal init(offer: PairingOffer, startedAtMilliseconds: UInt64) throws {
    let (expiry, overflow) = startedAtMilliseconds.addingReportingOverflow(
      offer.offerLifetimeMilliseconds)
    guard !overflow else { throw PairingOfferError.deadlineOverflow }
    self.startedAtMilliseconds = startedAtMilliseconds
    self.expiresAtMilliseconds = expiry
  }

  /// Whether the offer is still live on this monotonic clock.
  internal func isLive(nowMilliseconds: UInt64) -> Bool {
    nowMilliseconds >= startedAtMilliseconds && nowMilliseconds < expiresAtMilliseconds
  }
}
