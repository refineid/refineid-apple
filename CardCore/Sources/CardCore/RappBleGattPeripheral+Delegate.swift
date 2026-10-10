// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(CoreBluetooth) && canImport(RappEngine)
  @preconcurrency import CoreBluetooth

  extension RappBleGattPeripheral: CBPeripheralManagerDelegate {
    /// Publishes the service once Bluetooth is on.
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
      stateChanged(peripheral.state)
    }

    /// The requester enabled indications on a characteristic.
    public func peripheralManager(
      _: CBPeripheralManager,
      central: CBCentral,
      didSubscribeTo characteristic: CBCharacteristic
    ) {
      subscribed(central, to: characteristic)
    }

    /// The requester disabled indications or went away.
    public func peripheralManager(
      _: CBPeripheralManager,
      central: CBCentral,
      didUnsubscribeFrom _: CBCharacteristic
    ) {
      unsubscribed(central)
    }

    /// A read of the bootstrap characteristic.
    public func peripheralManager(
      _: CBPeripheralManager,
      didReceiveRead request: CBATTRequest
    ) {
      read(request)
    }

    /// Writes on the channel characteristic.
    public func peripheralManager(
      _: CBPeripheralManager,
      didReceiveWrite requests: [CBATTRequest]
    ) {
      write(requests)
    }

    /// Room for the next indication.
    public func peripheralManagerIsReady(toUpdateSubscribers _: CBPeripheralManager) {
      readyToUpdate()
    }
  }
#endif
