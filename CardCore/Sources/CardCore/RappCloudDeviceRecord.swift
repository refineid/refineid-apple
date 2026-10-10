// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A device record synchronized through private iCloud (`NSUbiquitousKeyValueStore`).
///
/// Only public keys and device metadata are synced. Private keys remain exclusively
/// on the physical device that minted them.
public struct RappCloudDeviceRecord: Codable, Sendable, Equatable {
  // MARK: Properties

  /// Unique stable identifier of this device.
  public let deviceID: UUID
  /// Human-readable device name.
  public let deviceName: String
  /// Hardware model identifier.
  public let modelName: String
  /// The operational role of this device.
  public let role: RappDeviceRole
  /// 32-byte Curve25519 static public key of this device.
  public let staticPublicKey: Data
  /// Timestamp of the last update for freshness arbitration.
  public let updatedAt: Date
  /// Application version string.
  public let appBuildVersion: String

  // MARK: Initialization

  /// Creates a new cloud device record snapshot.
  public init(
    deviceID: UUID,
    deviceName: String,
    modelName: String,
    role: RappDeviceRole,
    staticPublicKey: Data,
    updatedAt: Date = Date(),
    appBuildVersion: String = "1.0"
  ) {
    self.deviceID = deviceID
    self.deviceName = deviceName
    self.modelName = modelName
    self.role = role
    self.staticPublicKey = staticPublicKey
    self.updatedAt = updatedAt
    self.appBuildVersion = appBuildVersion
  }
}
