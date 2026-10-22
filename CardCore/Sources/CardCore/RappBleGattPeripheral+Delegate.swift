// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(CoreBluetooth) && canImport(RappEngine)
  @preconcurrency import CoreBluetooth

  extension RappBleGattPeripheral: CBPeripheralManagerDelegate {
    /// Publishes the service once Bluetooth is on.
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
      stateChanged(peripheral.state)
    }

    /// The service iOS kept published for a process it relaunched.
    public func peripheralManager(
      _: CBPeripheralManager,
      willRestoreState dict: [String: Any]
    ) {
      let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService]
      restore(services ?? [])
    }

    /// The system added the service.
    public func peripheralManager(
      _: CBPeripheralManager,
      didAdd _: CBService,
      error: (any Error)?
    ) {
      added(error: error)
    }

    /// Advertising started or failed to.
    public func peripheralManagerDidStartAdvertising(
      _: CBPeripheralManager,
      error: (any Error)?
    ) {
      advertisingStarted(error: error)
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
