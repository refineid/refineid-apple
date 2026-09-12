// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

// A candidate that is not a BLE candidate returns nil for its parameters.

/// The `fi.refineid.ble.v1` transport profile.
///
/// The engine owns the profile's name and the shape of its parameters, so a
/// caller never assembles either.
public enum BleProfile {
  /// The unique registered transport profile identifier for BLE.
  public static let name = "fi.refineid.ble.v1"

  /// The parameter key carrying a candidate's 128-bit service UUID string.
  public static let serviceUUIDKey = "service_uuid"

  /// The parameter key carrying an optional L2CAP PSM integer.
  public static let psmKey = "psm"

  /// The maximum allowed byte count for a service UUID string parameter.
  public static let maxServiceUUIDByteCount = 64

  /// Primary Service UUID for RefineID RAPP over BLE.
  public static let defaultServiceUUIDString = "FA1D0001-C34A-4836-843B-7603B5749A32"

  /// L2CAP PSM Characteristic UUID.
  public static let psmCharacteristicUUIDString = "FA1D0004-C34A-4836-843B-7603B5749A32"

  /// Fallback RX Stream Characteristic UUID.
  public static let rxCharacteristicUUIDString = "FA1D0002-C34A-4836-843B-7603B5749A32"

  /// Fallback TX Stream Characteristic UUID.
  public static let txCharacteristicUUIDString = "FA1D0003-C34A-4836-843B-7603B5749A32"

  /// Extracts the service UUID and optional PSM advertised by a transport candidate.
  internal static func parameters(of candidate: TransportCandidate) -> (
    serviceUUID: String, psm: UInt16?
  )? {
    guard candidate.profile == name,
      case .text(let uuid)? = candidate.parameters[serviceUUIDKey]
    else { return nil }
    var psm: UInt16?
    if case .unsigned(let value)? = candidate.parameters[psmKey] {
      psm = UInt16(clamping: value)
    }
    return (uuid, psm)
  }
}
