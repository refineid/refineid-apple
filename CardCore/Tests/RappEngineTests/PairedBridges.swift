// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RappEngine

/// Both endpoints' pair records, as the bridges hold them.
internal struct PairedBridges {
  internal let requester: RappPairRecord
  internal let custodian: RappPairRecord

  /// A fresh pairing granting `grants`, confirmed on both sides.
  internal static func pair(granting grants: [ProfileName]) throws -> Self {
    let peers = try runPairing(offer: try makeOffer(profiles: grants), grants: grants)
    return Self(
      requester: RappPairRecord(record: peers.requester),
      custodian: RappPairRecord(record: peers.proxy))
  }
}
