// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import os

/// Whether this device's remote use is available now: on, and no card in a
/// reader attached to it (hierarchy specification §5.2, STPA CC-102).
///
/// Read from any thread: a pairing search asks it on its own executor
/// before it opens an endpoint. ``CardPresence`` reports the reader card.
internal enum RemoteUseAvailability {
  private static let readerCard = OSAllocatedUnfairLock(initialState: false)

  /// Whether remote use is on and no card is in a reader attached to this
  /// device; an iPad has no switch, and its remote use is on.
  internal static var isAvailable: Bool {
    #if os(macOS)
      guard RemoteAccessGate.isEnabled else { return false }
    #endif
    return !readerCard.withLock { $0 }
  }

  /// A card arrived in, or left, a reader attached to this device.
  internal static func readerCardChanged(present: Bool) {
    readerCard.withLock { $0 = present }
  }
}
