// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(CoreBluetooth) && canImport(RappEngine)
  @preconcurrency import CoreBluetooth

  extension RappBleGattCentral: CBCentralManagerDelegate, CBPeripheralDelegate {
    /// Scans once Bluetooth is on.
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
      stateChanged(central.state)
    }

    // swiftlint:disable legacy_objc_type
    /// One advertisement of a custodian.
    public func centralManager(
      _: CBCentralManager,
      didDiscover peripheral: CBPeripheral,
      advertisementData _: [String: Any],
      rssi: NSNumber
    ) {
      discovered(peripheral, rssi: rssi.intValue)
    }
    // swiftlint:enable legacy_objc_type

    /// The connection is up.
    public func centralManager(
      _: CBCentralManager,
      didConnect peripheral: CBPeripheral
    ) {
      connected(peripheral)
    }

    /// The connection could not be made.
    public func centralManager(
      _: CBCentralManager,
      didFailToConnect _: CBPeripheral,
      error _: (any Error)?
    ) {
      finish(.unreachable)
    }

    /// The custodian went away.
    public func centralManager(
      _: CBCentralManager,
      didDisconnectPeripheral _: CBPeripheral,
      error _: (any Error)?
    ) {
      disconnected()
    }

    /// The RAPP service was found.
    public func peripheral(
      _ peripheral: CBPeripheral,
      didDiscoverServices _: (any Error)?
    ) {
      discoveredServices(peripheral)
    }

    /// The channel and bootstrap characteristics were found.
    public func peripheral(
      _ peripheral: CBPeripheral,
      didDiscoverCharacteristicsFor service: CBService,
      error _: (any Error)?
    ) {
      discoveredCharacteristics(peripheral, service: service)
    }

    /// Indications are enabled on the channel.
    public func peripheral(
      _ peripheral: CBPeripheral,
      didUpdateNotificationStateFor _: CBCharacteristic,
      error: (any Error)?
    ) {
      notificationEnabled(peripheral, error: error)
    }

    /// The bootstrap read completed or an indication arrived.
    public func peripheral(
      _: CBPeripheral,
      didUpdateValueFor characteristic: CBCharacteristic,
      error: (any Error)?
    ) {
      valueUpdated(characteristic, error: error)
    }

    /// The custodian answered a write.
    public func peripheral(
      _: CBPeripheral,
      didWriteValueFor _: CBCharacteristic,
      error: (any Error)?
    ) {
      wrote(error: error)
    }
  }
#endif
