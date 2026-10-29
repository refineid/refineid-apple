// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What a requester's `fi.refineid.rapp.ble` link reports to its owner.
public enum RappBleGattEvent: Sendable, Equatable {
  /// The custodian refused the CPace step 1 written on the link with ATT
  /// error Insufficient Resources, and the requester read the bootstrap
  /// characteristic once more: a `pairing-busy`, or an offer, which counts
  /// as busy with no wait (§4.2, "Busy Refusal" item 2). The link closes
  /// next.
  case attemptRefused(Data)
  /// The requester read the custodian's bootstrap answer off the bootstrap
  /// characteristic: its offer, from which the pairing ceremony starts, or
  /// a `pairing-busy`.
  case bootstrap(Data)
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
