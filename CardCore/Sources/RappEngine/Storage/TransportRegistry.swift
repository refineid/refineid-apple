// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The transport profiles an offer may name and the exact entry each one
/// carries (RAPP v26.10.9 §2.2, §4.2).
///
/// `apple-peer-v1` is this implementation's Apple-to-Apple tier: it is not
/// in the specification's registry and only Apple peers offer or accept it.
internal enum TransportRegistry {
  /// The stream profile's one candidate identifier (§2.2).
  internal static let streamCandidateIdentifier = "stream-1"

  internal static let applePeerProfile = "apple-peer-v1"
  internal static let applePeerCandidateIdentifier = "apple-peer-v1.nearby"

  /// The offer entry for `profile`, or nothing for an unregistered one.
  internal static func entry(for profile: String) -> TransportCandidate? {
    switch profile {
    case RappBleGattProfile.name:
      RappBleGattProfile.candidate

    case StreamProfile.name:
      TransportCandidate(
        profile: profile, candidateIdentifier: streamCandidateIdentifier, parameters: [:])

    case applePeerProfile:
      TransportCandidate(
        profile: profile, candidateIdentifier: applePeerCandidateIdentifier, parameters: [:])

    default:
      nil
    }
  }
}
