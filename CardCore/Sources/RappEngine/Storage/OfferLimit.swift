// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Sizes and ceilings the specification fixes for a pairing offer.
internal enum OfferLimit {
  internal static let offerIdentifierSize = 32
  internal static let pairingSecretSize = 32
  internal static let transportCandidates = 8
  internal static let offerLifetimeMaximumMilliseconds: UInt64 = 180_000
  internal static let encodedOfferSize = 1_024
}

/// The pairing suite every offer must list.
internal let mandatoryPairingSuite = RappNoise.pairingSuite
