// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What a requester's `fi.refineid.rapp.ble` link reports to its owner.
public enum RappBleGattEvent: Sendable, Equatable {
  /// The requester read the custodian's offer off the bootstrap
  /// characteristic; the pairing ceremony starts from it.
  case bootstrapOffer(Data)
  /// The link ended and will deliver nothing more.
  case closed(RappBleGattFailure)
  /// Routing finished: the custodian acknowledged the preamble. Protocol
  /// frames may flow from here on.
  case connected
  /// One complete, reassembled protocol frame.
  case frame(Data)
  /// The link goes to this advertiser; its routing outcome follows as
  /// ``connected`` or a close.
  case peer(UUID)
  /// One step, for a development trace.
  case trace(RappBleGattTrace)
}
