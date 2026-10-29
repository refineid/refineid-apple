// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Why a `fi.refineid.rapp.ble` link ended.
public enum RappBleGattFailure: Error, Sendable, Equatable {
  /// The custodian could not admit the CPace step 1 written on the link
  /// and refused it with ATT error Insufficient Resources (§4.2, "Busy
  /// Refusal").
  case attemptRefused
  /// The negotiated ATT MTU is below 512 (§5.2 step 1).
  case attMtuTooSmall
  /// Bluetooth is off, unauthorized, or unsupported here.
  case bluetoothUnavailable
  /// The owner cancelled the link.
  case cancelled
  /// The peer disconnected or unsubscribed.
  case disconnected
  /// Pre-authentication invalid input other than a broken segment: a
  /// write before indications were enabled, on another characteristic, or
  /// at an offset (§5.2).
  case protocolViolation
  /// A fragment broke the segmentation rules or its frame did not finish
  /// within the reassembly timer (§5.3).
  case reassemblyFailed
  /// The custodian refused the routing preamble: the tag routes to no
  /// pairing it serves, its nonce was routed before, or it serves another
  /// session (§2.2.1).
  case routingRefused
  /// No custodian was found, or the connection or discovery failed.
  case unreachable
}
