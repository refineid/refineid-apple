// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore

  /// The account's directory of same-account devices, as forgetting every
  /// pairing sees it.
  internal protocol SameAccountDirectory: Sendable {
    /// Removes every device this one pairs with, so none of them pairs with
    /// it again; false when the directory could not be reached.
    func removeComplementaryDevices() async -> Bool
  }

  extension RappAutoPairingService: SameAccountDirectory {}

#endif
