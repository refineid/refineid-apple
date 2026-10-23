// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import Foundation

  /// What stops remote use while it is on: this Mac's Bluetooth, or a
  /// permission macOS was refused.
  internal enum RemoteUseBlockage: Equatable, Sendable {
    /// macOS does not let this app use Bluetooth.
    case bluetoothNotAllowed

    /// The Mac's Bluetooth is off.
    case bluetoothOff

    /// macOS does not let this app use the local network.
    case localNetworkNotAllowed

    /// The cause, as the switch's help and accessibility value name it.
    internal var cause: String {
      switch self {
      case .bluetoothNotAllowed:
        String(localized: "Bluetooth is not allowed")

      case .bluetoothOff:
        String(localized: "Bluetooth is off")

      case .localNetworkNotAllowed:
        String(localized: "local network is not allowed")
      }
    }
  }

#endif
