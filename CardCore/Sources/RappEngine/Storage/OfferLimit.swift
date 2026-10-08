// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Sizes and ceilings RAPP v26.10.1 §3.3 and §4.2 fix for a pairing offer.
internal enum OfferLimit {
  internal static let offerIdentifierSize = 32
  internal static let transportCandidates = 8
  internal static let offerLifetimeMaximumMilliseconds: UInt64 = 60_000
  internal static let encodedOfferSize = 1_024
}
