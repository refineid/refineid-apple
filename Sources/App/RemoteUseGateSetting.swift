// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import RappRequester

  /// The holder's remote-use choice as the switch reads and records it,
  /// kept where the device keeps it.
  @MainActor
  internal final class RemoteUseGateSetting: RemoteUseSetting {
    /// Whether remote transports may run now.
    internal var isEnabled: Bool {
      RemoteAccessGate.isEnabled
    }

    /// Records the choice where the device keeps it.
    internal func setEnabled(_ enabled: Bool) {
      RemoteAccessGate.setEnabled(enabled)
    }
  }

#endif
