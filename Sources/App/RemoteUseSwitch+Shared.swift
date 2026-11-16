// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import RappRequester

  extension RemoteUseSwitch {
    /// The app's one switch: the two watches that ask for the permissions,
    /// and the registry that follows the paired phone.
    @MainActor internal static let shared = RemoteUseSwitch(
      bluetooth: BluetoothReadinessWatch(),
      localNetwork: LocalNetworkPermissionWatch()
    ) { move in
      PersistentTokenRegistry.shared.remoteUseChanged(move)
    }
  }

#endif
