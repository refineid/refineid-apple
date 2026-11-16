// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import RappRequester

  extension RemoteUseBlockage {
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
