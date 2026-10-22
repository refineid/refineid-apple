// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Platform-facing numbers of the `fi.refineid.rapp.ble` link.
internal enum RappBleGattLimit {
  /// Bytes the ATT PDU header takes from the MTU, which the platform's
  /// reported value lengths already exclude.
  internal static let attHeaderSize = 3
  /// How long the requester gathers advertisers after the first before it
  /// dials the strongest, in milliseconds; the advertiser that routed last
  /// is dialed at once.
  internal static let choiceWindowMilliseconds = 1_000
  /// The RSSI Core Bluetooth reports when none was available, in dBm
  /// (`centralManager(_:didDiscover:advertisementData:rssi:)`).
  internal static let unavailableRssi = 127
}
