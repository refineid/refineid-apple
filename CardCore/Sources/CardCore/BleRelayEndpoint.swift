// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(CoreBluetooth)
  import CoreBluetooth
#endif

/// A Bluetooth Low Energy endpoint definition for RefineID RAPP.
public struct BleRelayEndpoint: Sendable, Equatable {
  /// The 128-bit Primary Service UUID string.
  public let serviceUUIDString: String
  /// The optional L2CAP PSM if statically assigned or known ahead of time.
  public let psm: UInt16?

  #if canImport(CoreBluetooth)
    /// The parsed CoreBluetooth CBUUID.
    public var cbuuid: CBUUID {
      CBUUID(string: serviceUUIDString)
    }
  #endif

  /// Creates a BLE endpoint with a service UUID and optional PSM.
  public init(
    serviceUUIDString: String = "FA1D0001-C34A-4836-843B-7603B5749A32",
    psm: UInt16? = nil
  ) {
    self.serviceUUIDString = serviceUUIDString
    self.psm = psm
  }
}
