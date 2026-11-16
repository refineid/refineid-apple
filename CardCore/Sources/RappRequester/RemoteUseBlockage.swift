// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// What stops remote use while it is on: this computer's Bluetooth, or a
/// permission the platform was refused.
public enum RemoteUseBlockage: Equatable, Sendable {
  /// The platform does not let this app use Bluetooth.
  case bluetoothNotAllowed

  /// The computer's Bluetooth is off.
  case bluetoothOff

  /// The platform does not let this app use the local network.
  case localNetworkNotAllowed
}
