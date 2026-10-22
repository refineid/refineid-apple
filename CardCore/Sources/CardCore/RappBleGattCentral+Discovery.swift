// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(CoreBluetooth) && canImport(RappEngine)
  @preconcurrency import CoreBluetooth
  import RappEngine

  /// How the requester finds its custodian and readies the link: scan,
  /// choose, connect, discover, check the MTU, enable indications.
  extension RappBleGattCentral {
    /// Orders signal strengths, an unavailable one weakest.
    private static func strength(_ rssi: Int) -> Int {
      rssi == RappBleGattLimit.unavailableRssi ? Int.min : rssi
    }

    internal func stateChanged(_ state: CBManagerState) {
      onEvent(.trace(.radio(RappBleGattPeripheral.radioState(state))))
      switch state {
      case .poweredOn:
        let service = CBUUID(string: RappBleGattProfile.serviceUUIDString)
        // A custodian this computer is already connected to, for another
        // client or an earlier link, may advertise slowly; it counts as
        // seen, with no signal strength.
        for connected in manager?.retrieveConnectedPeripherals(withServices: [service]) ?? [] {
          discovered(connected, rssi: RappBleGattLimit.unavailableRssi)
        }
        guard peripheral == nil else { return }
        manager?.scanForPeripherals(
          withServices: [service],
          options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        onEvent(.trace(.scanning))

      case .poweredOff, .unauthorized, .unsupported:
        finish(.bluetoothUnavailable)

      default:
        break
      }
    }

    /// Dials the advertiser that routed last at once; otherwise gathers
    /// advertisers for the choice window and dials the strongest.
    internal func discovered(_ found: CBPeripheral, rssi: Int) {
      guard peripheral == nil, !finished, !peers.avoided.contains(found.identifier) else {
        return
      }
      onEvent(.trace(.discovered(peer: found.identifier, rssi: rssi)))
      guard found.identifier != peers.preferred else {
        connect(found)
        return
      }
      let strongest = max(candidates[found.identifier]?.rssi ?? rssi, rssi)
      candidates[found.identifier] = (found, strongest)
      guard !choosing else { return }
      choosing = true
      queue.asyncAfter(
        deadline: .now() + .milliseconds(RappBleGattLimit.choiceWindowMilliseconds)
      ) { [weak self] in
        self?.choose()
      }
    }

    internal func connected(_ connected: CBPeripheral) {
      connected.discoverServices([CBUUID(string: RappBleGattProfile.serviceUUIDString)])
    }

    internal func discoveredServices(_ found: CBPeripheral) {
      guard
        let service = found.services?.first(where: { service in
          service.uuid == CBUUID(string: RappBleGattProfile.serviceUUIDString)
        })
      else {
        finish(.unreachable)
        return
      }
      found.discoverCharacteristics(
        [
          CBUUID(string: RappBleGattProfile.channelUUIDString),
          CBUUID(string: RappBleGattProfile.bootstrapUUIDString),
        ], for: service)
    }

    /// Reads the negotiated MTU, which the system has settled by now, and
    /// enables indications only on a link that may carry RAPP (§5.2 step 1,
    /// STPA CC-52).
    internal func discoveredCharacteristics(_ found: CBPeripheral, service: CBService) {
      channel = service.characteristics?.first { characteristic in
        characteristic.uuid == CBUUID(string: RappBleGattProfile.channelUUIDString)
      }
      bootstrap = service.characteristics?.first { characteristic in
        characteristic.uuid == CBUUID(string: RappBleGattProfile.bootstrapUUIDString)
      }
      guard let channel, channel.properties.contains(.indicate) else {
        finish(.unreachable)
        return
      }
      let attMtu =
        found.maximumWriteValueLength(for: .withoutResponse) + RappBleGattLimit.attHeaderSize
      onEvent(.trace(.connected(peer: found.identifier, attMtu: attMtu)))
      do {
        capacity = try RappBleSar.payloadCapacity(
          negotiatedAttMtu: attMtu,
          platformValueLimit: found.maximumWriteValueLength(for: .withResponse))
      } catch {
        finish(.attMtuTooSmall)
        return
      }
      found.setNotifyValue(true, for: channel)
      onEvent(.trace(.indicationsRequested))
    }

    internal func notificationEnabled(_ found: CBPeripheral, error: (any Error)?) {
      guard !finished, !routed else { return }
      guard error == nil, channel?.isNotifying == true else {
        finish(.unreachable)
        return
      }
      switch purpose {
      case .pairing:
        guard let bootstrap else {
          finish(.unreachable)
          return
        }
        found.readValue(for: bootstrap)

      case .session:
        sendPreamble()
      }
    }

    private func choose() {
      guard peripheral == nil, !finished else { return }
      let ranked = candidates.values.max { lower, higher in
        Self.strength(lower.rssi) < Self.strength(higher.rssi)
      }
      guard let chosen = ranked else { return }
      connect(chosen.peripheral)
    }

    private func connect(_ found: CBPeripheral) {
      peripheral = found
      candidates.removeAll()
      found.delegate = self
      if manager?.isScanning == true { manager?.stopScan() }
      onEvent(.peer(found.identifier))
      onEvent(.trace(.connecting(peer: found.identifier)))
      manager?.connect(found)
    }
  }
#endif
