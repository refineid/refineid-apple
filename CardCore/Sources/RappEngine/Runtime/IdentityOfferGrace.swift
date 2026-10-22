// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// How long a requester keeps offering a certificate the custodian confirmed
/// while no session is open or the custodian reports absence, with no
/// report of the card present in that time (RAPP v26.10.22 §8.4 item 3).
internal enum IdentityOfferGrace {
  /// The grace, in milliseconds.
  internal static let milliseconds: UInt64 = 120_000
}
