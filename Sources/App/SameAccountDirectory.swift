// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import Foundation

  /// The account's directory of same-account devices, as forgetting every
  /// pairing sees it.
  internal protocol SameAccountDirectory: Sendable {
    /// Removes exactly the devices whose same-account pairing with this one
    /// has one of `pairIDs`, so none of them pairs with it again; true once
    /// the directory, read again, holds none of them, false while it does
    /// or cannot be reached.
    func removeDevices(pairedThrough pairIDs: Set<Data>) async -> Bool
  }

  extension RappAutoPairingService: SameAccountDirectory {}

#endif
