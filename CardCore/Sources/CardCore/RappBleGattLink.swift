// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One central's link to the custodian's GATT server: from the central
/// enabling indications until it disables them or the owner closes it.
public struct RappBleGattLink: Hashable, Sendable {
  /// Names this link apart from every earlier link of the same central.
  public let identifier: UUID
  /// The central, as Core Bluetooth names it on this device.
  public let central: UUID
}
