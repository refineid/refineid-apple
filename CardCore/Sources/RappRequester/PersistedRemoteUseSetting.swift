// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore

/// The choice the app persists: ``RemoteAccessGate``.
public final class PersistedRemoteUseSetting: RemoteUseSetting {
  /// Whether remote transports may run now.
  public var isEnabled: Bool {
    RemoteAccessGate.isEnabled
  }

  /// A setting over the app's stored choice, which holds nothing itself.
  public init() {
    // The choice lives in the gate, so this object has nothing to set up.
  }

  /// Records the choice where the device keeps it.
  public func setEnabled(_ enabled: Bool) {
    RemoteAccessGate.setEnabled(enabled)
  }
}
