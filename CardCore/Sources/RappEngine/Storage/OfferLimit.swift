// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Sizes RAPP v26.10.21 §3.3 and §4.2 fix for a pairing offer.
internal enum OfferLimit {
  internal static let offerIdentifierSize = 32
  internal static let transportCandidates = 8
  /// Every offer lives exactly 5 minutes (§3.3 item 7).
  internal static let offerLifetimeMilliseconds: UInt64 = 300_000
  /// The ATT value capacity at the minimum MTU bounds every offer (§4.2).
  internal static let encodedOfferSize = 509
}
