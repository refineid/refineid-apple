// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(CoreBluetooth) && canImport(RappEngine)
  @preconcurrency import CoreBluetooth
  import RappEngine

  /// The requester end of `fi.refineid.rapp.ble.v1`: the GATT central
  /// (RAPP v26.10.1 §4.4, §5.2).
  ///
  /// It connects to a custodian whose median RSSI clears the proximity
  /// threshold, checks the MTU, enables indications, reads the offer for a
  /// pairing, writes the routing preamble, and then carries frames: each
  /// fragment a write with response, the next only after the response.
  public final class RappBleGattCentral: NSObject, @unchecked Sendable {
    private let purpose: RappBleRoutingPurpose
    private let minimumRssi: Int
    private let onEvent: @Sendable (RappBleGattEvent) -> Void
    private let queue = DispatchQueue(label: "fi.refineid.rapp-ble-central")

    private var manager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var channel: CBCharacteristic?
    private var bootstrap: CBCharacteristic?
    private var rssiSamples: [UUID: [Int]] = [:]
    private var capacity = 0
    private var routed = false
    private var reassembler = RappBleSarReassembler()
    private var outbound: [Data] = []
    private var sendCompletion: CheckedContinuation<Void, any Error>?
    private var finished = false

    /// A requester opening a link for `purpose`.
    ///
    /// `minimumRssi` is the §4.4 threshold; only an isolated development
    /// setup may lower it.
    @preconcurrency
    public init(
      purpose: RappBleRoutingPurpose,
      minimumRssi: Int = -55,
      onEvent: @escaping @Sendable (RappBleGattEvent) -> Void
    ) {
      self.purpose = purpose
      self.minimumRssi = minimumRssi
      self.onEvent = onEvent
      super.init()
    }

    /// Starts scanning once Bluetooth is powered on.
    public func start() {
      queue.async { [weak self] in
        guard let self, !finished else { return }
        manager = CBCentralManager(delegate: self, queue: queue)
      }
    }

    /// Writes one protocol frame, fragment by fragment, each acknowledged
    /// before the next.
    public func send(_ frame: Data) async throws {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        queue.async { [weak self] in
          guard let self else {
            continuation.resume(throwing: RappBleGattFailure.disconnected)
            return
          }
          enqueue(frame, continuation: continuation)
        }
      }
    }

    private func enqueue(_ frame: Data, continuation: CheckedContinuation<Void, any Error>) {
      guard !finished, routed, capacity > 0 else {
        continuation.resume(throwing: RappBleGattFailure.disconnected)
        return
      }
      guard sendCompletion == nil else {
        continuation.resume(throwing: RappBleGattFailure.protocolViolation)
        return
      }
      do {
        outbound = try RappBleSar.segment(frame, capacity: capacity)
      } catch {
        continuation.resume(throwing: RappBleGattFailure.protocolViolation)
        return
      }
      sendCompletion = continuation
      writeNext()
    }

    /// Disconnects and ends the link.
    public func cancel() {
      queue.async { [weak self] in self?.finish(.cancelled) }
    }

    private func writeNext() {
      guard let peripheral, let channel else { return }
      guard let fragment = outbound.first else {
        let completion = sendCompletion
        sendCompletion = nil
        completion?.resume()
        return
      }
      peripheral.writeValue(fragment, for: channel, type: .withResponse)
    }

    internal func finish(_ failure: RappBleGattFailure) {
      guard !finished else { return }
      finished = true
      reassembler.reset()
      outbound.removeAll()
      let completion = sendCompletion
      sendCompletion = nil
      completion?.resume(throwing: failure)
      if let manager {
        if manager.isScanning { manager.stopScan() }
        if let peripheral { manager.cancelPeripheralConnection(peripheral) }
      }
      onEvent(.closed(failure))
    }

    private func armTimer() {
      queue.asyncAfter(
        deadline: .now() + .milliseconds(Int(RappBleSar.reassemblyTimeoutMilliseconds))
      ) { [weak self] in
        guard let self, !finished else { return }
        do {
          try reassembler.checkTimer(
            nowMilliseconds: RappPlatformClock().monotonicMilliseconds())
        } catch {
          finish(.protocolViolation)
        }
      }
    }

    /// Writes the routing preamble as one SINGLE fragment (§5.2).
    private func sendPreamble() {
      do {
        outbound = try RappBleSar.segment(try purpose.preamble(), capacity: capacity)
      } catch {
        finish(.protocolViolation)
        return
      }
      writeNext()
    }

    internal func stateChanged(_ state: CBManagerState) {
      switch state {
      case .poweredOn:
        manager?.scanForPeripherals(
          withServices: [CBUUID(string: RappBleGattProfile.serviceUUIDString)],
          options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])

      case .poweredOff, .unauthorized, .unsupported:
        finish(.bluetoothUnavailable)

      default:
        break
      }
    }

    /// Connects once the median of the latest samples clears the
    /// threshold by the hysteresis margin (§4.4).
    internal func discovered(_ found: CBPeripheral, rssi: Int) {
      guard peripheral == nil, !finished else { return }
      var samples = rssiSamples[found.identifier, default: []]
      samples.append(rssi)
      samples = Array(samples.suffix(RappBleGattLimit.rssiSampleCount))
      rssiSamples[found.identifier] = samples
      guard samples.count == RappBleGattLimit.rssiSampleCount else { return }
      let median = samples.sorted()[samples.count / RappBleGattLimit.medianDivisor]
      guard median >= minimumRssi + RappBleGattLimit.rssiHysteresis else { return }
      peripheral = found
      found.delegate = self
      manager?.stopScan()
      manager?.connect(found)
    }

    internal func connected(_ connected: CBPeripheral) {
      let atRequestMtu =
        connected.maximumWriteValueLength(for: .withoutResponse) + RappBleGattLimit.attHeaderSize
      do {
        capacity = try RappBleSar.payloadCapacity(
          negotiatedAttMtu: atRequestMtu,
          platformValueLimit: connected.maximumWriteValueLength(for: .withResponse))
      } catch {
        finish(.attMtuTooSmall)
        return
      }
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
      found.setNotifyValue(true, for: channel)
    }

    internal func notificationEnabled(_ found: CBPeripheral, error: (any Error)?) {
      guard error == nil else {
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

    internal func valueUpdated(_ characteristic: CBCharacteristic, error: (any Error)?) {
      guard error == nil, let value = characteristic.value else {
        finish(.protocolViolation)
        return
      }
      if characteristic.uuid == bootstrap?.uuid, !routed {
        onEvent(.bootstrapOffer(value))
        sendPreamble()
        return
      }
      guard characteristic.uuid == channel?.uuid, routed else {
        finish(.protocolViolation)
        return
      }
      do {
        if let message = try reassembler.receive(
          value, capacity: capacity,
          nowMilliseconds: RappPlatformClock().monotonicMilliseconds())
        {
          onEvent(.frame(message))
        } else {
          armTimer()
        }
      } catch {
        finish(.protocolViolation)
      }
    }

    internal func wrote(error: (any Error)?) {
      guard error == nil, !outbound.isEmpty else {
        finish(.disconnected)
        return
      }
      outbound.removeFirst()
      guard routed else {
        guard outbound.isEmpty else {
          writeNext()
          return
        }
        routed = true
        onEvent(.connected)
        return
      }
      writeNext()
    }

    internal func disconnected() {
      finish(.disconnected)
    }
  }
#endif
