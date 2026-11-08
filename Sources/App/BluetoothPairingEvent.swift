// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation

  /// What a pairing link reports to the ceremony on the main actor.
  internal enum BluetoothPairingEvent: Sendable {
    case closed(RappBleGattLink)
    case frame(RappBleGattLink, Data)
    case routed(RappBleGattLink)
  }
#endif
