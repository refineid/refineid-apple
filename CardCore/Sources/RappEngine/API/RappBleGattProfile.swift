// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The `fi.refineid.rapp.ble.v1` direct proximity profile (RAPP v26.10.1
/// §4.2, §5.1, §5.2).
///
/// The custodian is the GATT peripheral and the requester the central. The
/// requester writes with response; the custodian answers with indications.
public enum RappBleGattProfile {
  /// The registered transport profile name.
  public static let name = "fi.refineid.rapp.ble.v1"
  /// The one candidate identifier the profile binds.
  public static let candidateId = "ble-direct-1"
  /// The primary service, the only UUID the custodian advertises.
  public static let serviceUUIDString = "7E39FD01-A6B5-4D78-9E11-37E28E9545F1"
  /// The channel characteristic: write with response and indicate.
  public static let channelUUIDString = "7E39FD02-A6B5-4D78-9E11-37E28E9545F1"
  /// The bootstrap characteristic: read-only, carries the encoded offer.
  public static let bootstrapUUIDString = "7E39FD03-A6B5-4D78-9E11-37E28E9545F1"
  /// The generic local name the custodian may advertise (§4.1).
  public static let localName = "RefineID"
  /// The offer lifetime the profile fixes, in milliseconds.
  public static let offerLifetimeMilliseconds: UInt64 = 60_000
  /// The parameter key carrying the service UUID in the offer candidate.
  internal static let serviceUUIDKey = "service_uuid"

  /// The offer candidate this profile advertises.
  internal static var candidate: TransportCandidate {
    TransportCandidate(
      profile: name, candidateIdentifier: candidateId,
      parameters: [serviceUUIDKey: .text(serviceUUIDString)])
  }
}
