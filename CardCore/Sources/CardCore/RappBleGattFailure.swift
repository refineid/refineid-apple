// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Why a `fi.refineid.rapp.ble.v1` link ended.
public enum RappBleGattFailure: Error, Sendable, Equatable {
  /// The negotiated ATT MTU is below 512 (§5.2 step 1).
  case attMtuTooSmall
  /// Bluetooth is off, unauthorized, or unsupported here.
  case bluetoothUnavailable
  /// The owner cancelled the link.
  case cancelled
  /// The peer disconnected or unsubscribed.
  case disconnected
  /// Pre-authentication invalid input or a SAR violation (§5.2, §5.3).
  case protocolViolation
  /// No custodian was found, or the connection or discovery failed.
  case unreachable
}
