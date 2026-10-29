// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The one CPace attempt a BLE custodian runs at a time across all its
/// links (RAPP v26.10.29 §3.3 item 6).
///
/// The central whose step 1 was admitted holds the gate until its link
/// ends or is removed, however that happens; until then every other
/// central's step 1 is refused.
internal struct RappBleAttemptGate {
  /// The central whose CPace step 1 was admitted.
  private var holder: UUID?

  /// Admits the step 1 of `central` when no other central holds the gate.
  ///
  /// `admits` decides as well; the admitted central then holds the gate.
  internal mutating func admit(_ central: UUID, when admits: () -> Bool) -> Bool {
    guard holder == nil || holder == central, admits() else { return false }
    holder = central
    return true
  }

  /// Frees the gate when `central` holds it: its link ended or was removed.
  internal mutating func release(_ central: UUID) {
    if holder == central {
      holder = nil
    }
  }

  /// Frees the gate whoever holds it: every link is gone.
  internal mutating func releaseAll() {
    holder = nil
  }
}
