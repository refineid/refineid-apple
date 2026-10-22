// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The transport profiles an offer may name and the exact entry each one
/// carries (RAPP v26.10.21 §2.2, §4.2).
internal enum TransportRegistry {
  /// The stream profile's registered candidate identifier (§2.2).
  internal static let streamCandidateIdentifier = "stream"

  /// The offer entry for `profile`, or nothing for an unregistered one.
  internal static func entry(for profile: String) -> TransportCandidate? {
    switch profile {
    case RappBleGattProfile.name:
      RappBleGattProfile.candidate

    case StreamProfile.name:
      TransportCandidate(
        profile: profile, candidateIdentifier: streamCandidateIdentifier, parameters: [:])

    default:
      nil
    }
  }
}
