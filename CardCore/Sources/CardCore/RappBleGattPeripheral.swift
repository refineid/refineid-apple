// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(CoreBluetooth) && canImport(RappEngine)
  @preconcurrency import CoreBluetooth
  import RappEngine

  /// The custodian end of `fi.refineid.rapp.ble.v1`: the GATT peripheral
  /// (RAPP v26.10.9 §5.1, §5.2).
  ///
  /// It advertises only the RAPP service UUID and a generic name, serves
  /// the offer on the bootstrap characteristic, receives the requester's
  /// writes on the channel characteristic, and answers with indications.
  /// One central at a time; every connection starts in `Phase::Routing`.
  public final class RappBleGattPeripheral: NSObject, @unchecked Sendable {
    /// Decides whether a routing preamble may proceed.
    public typealias Admission = @Sendable (RappBleRoutingPurpose) -> Bool

    private let bootstrapOffer: Data?
    private let admits: Admission
    private let onEvent: @Sendable (RappBleGattEvent) -> Void
    private let queue = DispatchQueue(label: "fi.refineid.rapp-ble-peripheral")

    private var manager: CBPeripheralManager?
    private var channel: CBMutableCharacteristic?
    private var central: CBCentral?
    private var capacity = 0
    private var routed = false
    private var reassembler = RappBleSarReassembler()
    private var outbound: [Data] = []
    private var sendCompletion: CheckedContinuation<Void, any Error>?
    private var finished = false

    /// A custodian serving `bootstrapOffer` (for pairing; nil when only
    /// stored pairings may reconnect) and admitting the preambles `admits`
    /// accepts.
    @preconcurrency
    public init(
      bootstrapOffer: Data?,
      admits: @escaping Admission,
      onEvent: @escaping @Sendable (RappBleGattEvent) -> Void
    ) {
      self.bootstrapOffer = bootstrapOffer
      self.admits = admits
      self.onEvent = onEvent
      super.init()
    }

    /// Starts advertising once Bluetooth is powered on.
    public func start() {
      queue.async { [weak self] in
        guard let self, !finished else { return }
        manager = CBPeripheralManager(delegate: self, queue: queue)
      }
    }

    /// Indicates one protocol frame, fragment by fragment.
    ///
    /// The attribute protocol allows one outstanding indication, so each
    /// fragment is confirmed before the next leaves (§5.2 backpressure).
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
      drainOutbound()
    }

    /// Stops advertising and ends the link.
    public func cancel() {
      queue.async { [weak self] in self?.finish(.cancelled) }
    }

    private func drainOutbound() {
      guard let manager, let channel, let central else { return }
      while let fragment = outbound.first {
        guard
          manager.updateValue(fragment, for: channel, onSubscribedCentrals: [central])
        else { return }
        outbound.removeFirst()
      }
      let completion = sendCompletion
      sendCompletion = nil
      completion?.resume()
    }

    private func publish() {
      let made = CBMutableCharacteristic(
        type: CBUUID(string: RappBleGattProfile.channelUUIDString),
        properties: [.write, .indicate],
        value: nil,
        permissions: [.writeable])
      let bootstrap = CBMutableCharacteristic(
        type: CBUUID(string: RappBleGattProfile.bootstrapUUIDString),
        properties: [.read],
        value: nil,
        permissions: [.readable])
      let service = CBMutableService(
        type: CBUUID(string: RappBleGattProfile.serviceUUIDString), primary: true)
      service.characteristics = [made, bootstrap]
      channel = made
      manager?.add(service)
      manager?.startAdvertising([
        CBAdvertisementDataServiceUUIDsKey: [service.uuid],
        CBAdvertisementDataLocalNameKey: RappBleGattProfile.localName,
      ])
    }

    /// Accepts one complete frame in the phase the link is in.
    private func deliver(_ message: Data) {
      guard routed else {
        guard let purpose = RappBleRoutingPurpose(preamble: message), admits(purpose) else {
          finish(.protocolViolation)
          return
        }
        routed = true
        onEvent(.connected)
        return
      }
      onEvent(.frame(message))
    }

    private func receive(_ fragment: Data) {
      let now = RappPlatformClock().monotonicMilliseconds()
      do {
        if let message = try reassembler.receive(
          fragment, capacity: capacity, nowMilliseconds: now)
        {
          deliver(message)
        } else {
          armTimer()
        }
      } catch {
        finish(.protocolViolation)
      }
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

    internal func finish(_ failure: RappBleGattFailure) {
      guard !finished else { return }
      finished = true
      reassembler.reset()
      outbound.removeAll()
      let completion = sendCompletion
      sendCompletion = nil
      completion?.resume(throwing: failure)
      if let manager {
        manager.stopAdvertising()
        manager.removeAllServices()
      }
      central = nil
      onEvent(.closed(failure))
    }

    internal func stateChanged(_ state: CBManagerState) {
      switch state {
      case .poweredOn:
        publish()

      case .poweredOff, .unauthorized, .unsupported:
        finish(.bluetoothUnavailable)

      default:
        break
      }
    }

    internal func subscribed(_ subscriber: CBCentral, to characteristic: CBCharacteristic) {
      guard characteristic.uuid == channel?.uuid else { return }
      guard central == nil else { return }
      do {
        capacity = try RappBleSar.payloadCapacity(
          negotiatedAttMtu: subscriber.maximumUpdateValueLength + RappBleGattLimit.attHeaderSize)
      } catch {
        finish(.attMtuTooSmall)
        return
      }
      central = subscriber
      manager?.stopAdvertising()
    }

    internal func unsubscribed(_ subscriber: CBCentral) {
      guard subscriber.identifier == central?.identifier else { return }
      finish(.disconnected)
    }

    internal func read(_ request: CBATTRequest) {
      guard request.characteristic.uuid == CBUUID(string: RappBleGattProfile.bootstrapUUIDString),
        let bootstrapOffer
      else {
        manager?.respond(to: request, withResult: .readNotPermitted)
        return
      }
      guard request.offset <= bootstrapOffer.count else {
        manager?.respond(to: request, withResult: .invalidOffset)
        return
      }
      request.value = bootstrapOffer.subdata(in: request.offset..<bootstrapOffer.count)
      manager?.respond(to: request, withResult: .success)
    }

    internal func write(_ requests: [CBATTRequest]) {
      guard let first = requests.first else { return }
      // A preamble before indications are enabled, a second central, or a
      // write anywhere but the channel is pre-authentication invalid input.
      guard requests.allSatisfy({ $0.characteristic.uuid == channel?.uuid }),
        let central, requests.allSatisfy({ $0.central.identifier == central.identifier })
      else {
        manager?.respond(to: first, withResult: .writeNotPermitted)
        if self.central != nil { finish(.protocolViolation) }
        return
      }
      manager?.respond(to: first, withResult: .success)
      for request in requests {
        guard request.offset == 0, let value = request.value else {
          finish(.protocolViolation)
          return
        }
        receive(value)
        if finished { return }
      }
    }

    internal func readyToUpdate() {
      guard sendCompletion != nil else { return }
      drainOutbound()
    }
  }
#endif
