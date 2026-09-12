// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(CoreBluetooth)
  import CoreBluetooth

  // MARK: - CoreBluetooth Delegates

  extension BleRelaySession: CBCentralManagerDelegate, CBPeripheralDelegate,
    CBPeripheralManagerDelegate
  {
    // MARK: - CBCentralManagerDelegate

    /// Handles updates to the central manager's operational state.
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
      handleCentralStateChange(central.state)
    }

    // swiftlint:disable legacy_objc_type
    /// Handles peripheral discovery during central scanning.
    public func centralManager(
      _: CBCentralManager,
      didDiscover peripheral: CBPeripheral,
      advertisementData _: [String: Any],
      rssi _: NSNumber
    ) {
      handleDiscoveredPeripheral(peripheral)
    }
    // swiftlint:enable legacy_objc_type

    /// Handles successful connection to a discovered peripheral.
    public func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
      handleConnectedPeripheral(peripheral)
    }

    /// Handles failed connection attempts to a discovered peripheral.
    public func centralManager(
      _: CBCentralManager,
      didFailToConnect _: CBPeripheral,
      error _: (any Error)?
    ) {
      finish(with: .unreachable)
    }

    // MARK: - CBPeripheralDelegate

    /// Handles service discovery on a connected peripheral.
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices _: (any Error)?) {
      handleDiscoveredServices(peripheral)
    }

    /// Handles characteristic discovery for a peripheral service.
    public func peripheral(
      _ peripheral: CBPeripheral,
      didDiscoverCharacteristicsFor service: CBService,
      error _: (any Error)?
    ) {
      handleDiscoveredCharacteristics(peripheral, service: service)
    }

    /// Handles characteristic value updates for PSM retrieval.
    public func peripheral(
      _ peripheral: CBPeripheral,
      didUpdateValueFor characteristic: CBCharacteristic,
      error _: (any Error)?
    ) {
      handleCharacteristicValue(characteristic, peripheral: peripheral)
    }

    /// Handles the opening of an L2CAP channel on a peripheral.
    public func peripheral(
      _: CBPeripheral,
      didOpen channel: CBL2CAPChannel?,
      error: (any Error)?
    ) {
      handleOpenedChannel(channel, error: error)
    }

    // MARK: - CBPeripheralManagerDelegate

    /// Handles updates to the peripheral manager's operational state.
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
      handlePeripheralStateChange(peripheral.state)
    }

    /// Handles publishing of the L2CAP channel on the peripheral manager.
    public func peripheralManager(
      _: CBPeripheralManager,
      didPublishL2CAPChannel psm: CBL2CAPPSM,
      error: (any Error)?
    ) {
      handlePublishedL2CAPChannel(psm: psm, error: error)
    }

    /// Handles incoming L2CAP channel connections on the peripheral manager.
    public func peripheralManager(
      _: CBPeripheralManager,
      didOpen channel: CBL2CAPChannel?,
      error: (any Error)?
    ) {
      handleOpenedChannel(channel, error: error)
    }

    // MARK: - Internal Central Logic

    private func handleCentralStateChange(_ state: CBManagerState) {
      guard case .central(let endpoint, _) = mode else { return }
      if state == .poweredOn {
        centralManager?.scanForPeripherals(
          withServices: [endpoint.cbuuid],
          options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
      } else if state == .poweredOff || state == .unauthorized || state == .unsupported {
        finish(with: .bluetoothUnavailable)
      }
    }

    private func handleDiscoveredPeripheral(_ peripheral: CBPeripheral) {
      guard connectedPeripheral == nil else { return }
      connectedPeripheral = peripheral
      centralManager?.stopScan()

      peripheral.delegate = self
      centralManager?.connect(peripheral, options: nil)
    }

    private func handleConnectedPeripheral(_ peripheral: CBPeripheral) {
      guard case .central(let endpoint, _) = mode else { return }
      if let psm = endpoint.psm {
        peripheral.openL2CAPChannel(CBL2CAPPSM(psm))
      } else {
        peripheral.discoverServices([endpoint.cbuuid])
      }
    }

    private func handleDiscoveredServices(_ peripheral: CBPeripheral) {
      guard case .central(let endpoint, _) = mode else { return }
      guard let services = peripheral.services else { return }
      for service in services where service.uuid == endpoint.cbuuid {
        peripheral.discoverCharacteristics(
          [CBUUID(string: BleRelayEndpoint().serviceUUIDString)],
          for: service
        )
      }
    }

    private func handleDiscoveredCharacteristics(
      _ peripheral: CBPeripheral,
      service: CBService
    ) {
      guard let characteristics = service.characteristics else { return }
      let psmUUID = CBUUID(string: Constants.psmCharacteristicUUIDString)
      for characteristic in characteristics where characteristic.uuid == psmUUID {
        peripheral.readValue(for: characteristic)
        return
      }
      // If no characteristic, fallback to default PSM if known
      if case .central(let endpoint, _) = mode, let psm = endpoint.psm {
        peripheral.openL2CAPChannel(CBL2CAPPSM(psm))
      }
    }

    private func handleCharacteristicValue(
      _ characteristic: CBCharacteristic,
      peripheral: CBPeripheral
    ) {
      let psmUUID = CBUUID(string: Constants.psmCharacteristicUUIDString)
      if characteristic.uuid == psmUUID,
        let value = characteristic.value,
        value.count >= Constants.psmByteCount
      {
        let psm = value.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        peripheral.openL2CAPChannel(CBL2CAPPSM(psm))
      }
    }

    private func handleOpenedChannel(_ channel: CBL2CAPChannel?, error: (any Error)?) {
      guard error == nil, let channel else {
        finish(with: .unreachable)
        return
      }

      let handler = BleL2CAPChannelHandler(channel: channel) { [weak self] event in
        guard let self else { return }
        switch event {
        case .connected:
          if case .central(_, let preamble) = mode {
            Task { [weak self] in
              guard let self else { return }
              try? await channelHandler?.send(preamble)
              onEvent(.connected)
            }
          } else {
            onEvent(.connected)
          }

        case .frame(let data):
          onEvent(.frame(data))

        case .closed(let error):
          finish(with: error)
        }
      }

      channelHandler = handler
      handler.start()
    }

    // MARK: - Internal Peripheral Logic

    private func handlePeripheralStateChange(_ state: CBManagerState) {
      if state == .poweredOn {
        peripheralManager?.publishL2CAPChannel(withEncryption: false)
      } else if state == .poweredOff || state == .unauthorized || state == .unsupported {
        finish(with: .bluetoothUnavailable)
      }
    }

    private func handlePublishedL2CAPChannel(psm: CBL2CAPPSM, error: (any Error)?) {
      guard error == nil else {
        finish(with: .unreachable)
        return
      }
      assignedPsm = UInt16(psm)

      guard case .peripheral(let serviceUUIDString) = mode else { return }
      let serviceUUID = CBUUID(string: serviceUUIDString)
      let psmCharUUID = CBUUID(string: Constants.psmCharacteristicUUIDString)

      var psmBigEndian = UInt16(psm).bigEndian
      let psmData = withUnsafeBytes(of: &psmBigEndian) { Data($0) }

      let psmCharacteristic = CBMutableCharacteristic(
        type: psmCharUUID,
        properties: [.read],
        value: psmData,
        permissions: [.readable]
      )

      let service = CBMutableService(type: serviceUUID, primary: true)
      service.characteristics = [psmCharacteristic]

      peripheralManager?.add(service)
      peripheralManager?.startAdvertising([
        CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
        CBAdvertisementDataLocalNameKey: "RefineID-RAPP",
      ])
    }
  }
#endif
