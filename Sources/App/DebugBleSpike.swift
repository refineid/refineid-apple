// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG

  @preconcurrency import CoreBluetooth
  import Foundation

  /// Cable-side debug runner for the BLE RAPP spike.
  ///
  /// Runs a GATT Server on iPhone 15, advertises RAPP service,
  /// receives a request from Linux Central, sends back a response, and exits.
  @MainActor
  internal final class DebugBleSpike: NSObject, @preconcurrency CBPeripheralManagerDelegate {
    internal static let serviceUUIDString = "7E39FD01-A6B5-4D78-9E11-37E28E9545F1"
    internal static let charUUIDString = "7E39FD02-A6B5-4D78-9E11-37E28E9545F1"

    private static let timeoutSeconds = 300.0
    private static let pollIntervalNanoseconds: UInt64 = 100_000_000
    private static let signatureLength = 256
    private static let completionGracePeriodNanoseconds: UInt64 = 10_000_000_000
    private static let fillerByte = UInt8(ascii: "U")

    private var serviceUUID: CBUUID { CBUUID(string: Self.serviceUUIDString) }
    private var charUUID: CBUUID { CBUUID(string: Self.charUUIDString) }

    private var peripheralManager: CBPeripheralManager?
    private var char: CBMutableCharacteristic?
    private var connectedCentral: CBCentral?
    private var responsePayload: Data?
    private var lines: [String] = []
    private var done = false
    private var success = false

    internal static func run() async -> DebugModeReport {
      let runner = DebugBleSpike()
      return await runner.execute()
    }

    private func execute() async -> DebugModeReport {
      DebugConsole.emit("[BLE-SPIKE] Initializing CoreBluetooth Peripheral Manager...")
      peripheralManager = CBPeripheralManager(delegate: self, queue: nil)

      let deadline = Date(timeIntervalSinceNow: Self.timeoutSeconds)
      while !done, Date() < deadline {
        try? await Task.sleep(nanoseconds: Self.pollIntervalNanoseconds)
      }

      peripheralManager?.stopAdvertising()
      if !done {
        lines.append("[BLE-SPIKE] Timeout waiting for central connection/exchange")
      }
      return DebugModeReport(lines: lines, succeeded: success)
    }

    // MARK: - CBPeripheralManagerDelegate

    internal func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
      DebugConsole.emit("[BLE-SPIKE] Bluetooth state: \(peripheral.state.rawValue)")
      guard peripheral.state == .poweredOn else {
        lines.append(
          "[BLE-SPIKE] Error: Bluetooth not powered on (state \(peripheral.state.rawValue))"
        )
        done = true
        return
      }

      let characteristic = CBMutableCharacteristic(
        type: charUUID,
        properties: [.write, .writeWithoutResponse, .notify, .read],
        value: nil,
        permissions: [.readable, .writeable]
      )
      self.char = characteristic

      let service = CBMutableService(type: serviceUUID, primary: true)
      service.characteristics = [characteristic]

      peripheral.removeAllServices()
      peripheral.add(service)
    }

    internal func peripheralManager(
      _ peripheral: CBPeripheralManager,
      didAdd _: CBService,
      error: Error?
    ) {
      if let error {
        lines.append("[BLE-SPIKE] Failed to add service: \(error.localizedDescription)")
        done = true
        return
      }

      DebugConsole.emit("[BLE-SPIKE] Service added, starting advertising...")
      let advertisementData: [String: Any] = [
        CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
        CBAdvertisementDataLocalNameKey: "RefineID-RAPP",
      ]
      peripheral.startAdvertising(advertisementData)
    }

    internal func peripheralManagerDidStartAdvertising(
      _: CBPeripheralManager,
      error: Error?
    ) {
      if let error {
        lines.append("[BLE-SPIKE] Advertising failed: \(error.localizedDescription)")
        done = true
        return
      }
      DebugConsole.emit("[BLE-SPIKE] Advertising active for UUID \(serviceUUID.uuidString)")
    }

    internal func peripheralManager(
      _: CBPeripheralManager,
      central: CBCentral,
      didSubscribeTo _: CBCharacteristic
    ) {
      self.connectedCentral = central
      DebugConsole.emit(
        "[BLE-SPIKE] Central subscribed: \(central.identifier.uuidString) (MTU: \(central.maximumUpdateValueLength))"
      )
    }

    internal func peripheralManager(
      _ peripheral: CBPeripheralManager,
      didReceiveWrite requests: [CBATTRequest]
    ) {
      guard let firstRequest = requests.first else { return }
      guard firstRequest.characteristic.uuid == charUUID else {
        peripheral.respond(to: firstRequest, withResult: .requestNotSupported)
        return
      }

      var totalData = Data()
      for req in requests {
        if let val = req.value {
          totalData.append(val)
        }
      }

      DebugConsole.emit(
        "[BLE-SPIKE] Received write request (\(totalData.count) bytes in \(requests.count) chunks) from central!"
      )
      lines.append("[BLE-SPIKE] Received challenge frame: \(totalData.count) bytes")

      // Build synthetic 256-byte response signature
      var responseData = Data("RAPP-RESP:status=OK;sig=".utf8)
      responseData.append(
        Data(
          repeating: Self.fillerByte,
          count: Self.signatureLength - responseData.count
        )
      )
      self.responsePayload = responseData
      peripheral.respond(to: firstRequest, withResult: .success)

      if let char = self.char {
        let sent = peripheral.updateValue(
          responseData,
          for: char,
          onSubscribedCentrals: nil
        )
        DebugConsole.emit(
          "[BLE-SPIKE] Sent notification response (\(responseData.count) bytes, updateValue=\(sent))"
        )
        lines.append("[BLE-SPIKE] Sent response signature (\(responseData.count) bytes)")
      }
      success = true
      Task {
        try? await Task.sleep(nanoseconds: Self.completionGracePeriodNanoseconds)
        self.done = true
      }
    }

    internal func peripheralManager(
      _ peripheral: CBPeripheralManager,
      didReceiveRead request: CBATTRequest
    ) {
      if request.characteristic.uuid == charUUID {
        let data = self.responsePayload ?? Data("RAPP-READY".utf8)
        if request.offset > data.count {
          peripheral.respond(to: request, withResult: .invalidOffset)
          return
        }
        request.value = data.subdata(in: request.offset..<data.count)
        DebugConsole.emit(
          "[BLE-SPIKE] Delivered \(request.value?.count ?? 0) bytes via Read (offset \(request.offset))"
        )
        lines.append("[BLE-SPIKE] Delivered read: \(request.value?.count ?? 0) bytes")
        peripheral.respond(to: request, withResult: .success)
        if self.responsePayload != nil {
          done = true
        }
      } else {
        peripheral.respond(to: request, withResult: .requestNotSupported)
      }
    }
  }

#endif
