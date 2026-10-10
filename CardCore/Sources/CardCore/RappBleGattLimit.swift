// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Platform-facing numbers of the `fi.refineid.rapp.ble.v1` link.
internal enum RappBleGattLimit {
  /// Bytes the ATT PDU header takes from the MTU, which the platform's
  /// reported value lengths already exclude.
  internal static let attHeaderSize = 3
  /// Advertisements the requester samples before judging proximity (§4.4).
  internal static let rssiSampleCount = 3
  /// The proximity threshold the requester applies (§4.4), in dBm.
  internal static let minimumRssi = -55
  /// Divides an odd sample count down to its median's index.
  internal static let medianDivisor = 2
  /// The hysteresis applied around the threshold (§4.4), in dB.
  internal static let rssiHysteresis = 3
}
