// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

extension RappPairNames {
  /// The name to show for the pairing `pairID`: the one its peer
  /// introduced itself with, or a plain one when none is stored, so the
  /// pairing is still shown and used.
  internal static func displayName(forPairID pairID: Data) -> String {
    name(forPairID: pairID) ?? String(localized: "Paired device")
  }
}
