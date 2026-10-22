// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What the custodian's GATT server reports to its owner.
public enum RappBleGattServerEvent: Sendable, Equatable {
  /// The link ended and will deliver nothing more.
  case closed(RappBleGattLink, RappBleGattFailure)
  /// One complete, reassembled protocol frame on a routed link.
  case frame(RappBleGattLink, Data)
  /// The link's routing preamble was admitted; frames may flow.
  case routed(RappBleGattLink)
  /// One step, for a development trace.
  case trace(RappBleGattTrace)
}
