// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Where pairings are stored, implemented by the caller.
///
/// The engine holds no storage of its own; a pairing exists exactly where the
/// caller puts it, and the engine only asks.
public protocol RappPairVault: AnyObject, Sendable {
  /// Writes a pairing that must never leave this device.
  func insertDeviceOnly(pairId: Data, record: Data) throws

  /// Writes the confirmed pairing over the unconfirmed record stored under
  /// the same identifier (RAPP v26.10.21 §4.3 item 4), or the same record
  /// marked forgotten (§4.6 item 2).
  func replaceDeviceOnly(pairId: Data, record: Data) throws

  /// Reads a stored pairing, or nothing when none carries the identifier.
  func loadDeviceOnly(pairId: Data) throws -> Data?

  /// Destroys the pairing's keys and records when it ended.
  func revokeDeviceOnly(pairId: Data, revokedAtMs: UInt64) throws

  /// Whether the identifier names a pairing that has ended.
  func isRevoked(pairId: Data) throws -> Bool
}
