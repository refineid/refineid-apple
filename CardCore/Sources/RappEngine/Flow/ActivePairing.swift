// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Proof that both endpoints stored the pairing and confirmed it.
///
/// Each told the other (RAPP v26.10.18 §4.3 item 4); only
/// ``PairingStorage/intoActive()`` makes one.
internal struct ActivePairing: Equatable {
  internal let pairIdentifier: Data

  /// The stored record in its confirmed form, to be stored again over the
  /// unconfirmed one: the only way a record becomes confirmed.
  internal func confirm(_ record: PairRecord) throws -> PairRecord {
    guard record.pairIdentifier == pairIdentifier else {
      throw PairingError.pairIdentifierMismatch
    }
    return record.confirmed()
  }
}
