// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(CoreBluetooth) && canImport(RappEngine)
  @preconcurrency import CoreBluetooth
  import RappEngine

  /// The requester end of `fi.refineid.rapp.ble`: the GATT central
  /// (RAPP v26.10.29 §5.2).
  ///
  /// It scans for the RAPP service UUID, which also finds a custodian whose
  /// app advertises from the background (iOS moves the UUID to an overflow
  /// area only an explicit scan for it sees), and dials one advertiser:
  /// the one that routed last at once, else the strongest seen within the
  /// choice window, never one recently refused. No signal strength gates
  /// the dial; a relay cannot be told apart by it (§4.4). It reads the MTU
  /// before its first write and drops a link below 512, enables
  /// indications, reads the bootstrap answer for a pairing, writes the
  /// routing preamble, and then carries frames: each fragment a write with
  /// response, the next only after the response. A CPace step 1 the
  /// custodian refuses with ATT error Insufficient Resources is followed by one more
  /// read of the bootstrap characteristic, reported before the link closes.
  ///
  /// All state is confined to the central's queue; the delegate callbacks
  /// arrive on it.
  public final class RappBleGattCentral: NSObject, @unchecked Sendable {
    internal let purpose: RappBleRoutingPurpose
    internal let peers: RappBleCentralPeers
    internal let onEvent: @Sendable (RappBleGattEvent) -> Void
    internal let queue = DispatchQueue(label: "fi.refineid.rapp-ble-central")
    internal var manager: CBCentralManager?
    internal var peripheral: CBPeripheral?
    internal var channel: CBCharacteristic?
    internal var bootstrap: CBCharacteristic?
    internal var candidates: [UUID: (peripheral: CBPeripheral, rssi: Int)] = [:]
    internal var choosing = false
    internal var capacity = 0
    internal var routed = false
    /// Whether the custodian refused CPace step 1 and the bootstrap
    /// characteristic is being read once more.
    internal var rereadingBootstrap = false
    internal var finished = false
    private var reassembler = RappBleSarReassembler()
    private var outbound: [Data] = []
    private var sendCompletion: CheckedContinuation<Void, any Error>?

    /// A requester opening a link for `purpose` to one of `peers`.
    @preconcurrency
    public init(
      purpose: RappBleRoutingPurpose,
      peers: RappBleCentralPeers = RappBleCentralPeers(),
      onEvent: @escaping @Sendable (RappBleGattEvent) -> Void
    ) {
      self.purpose = purpose
      self.peers = peers
      self.onEvent = onEvent
      super.init()
    }

    /// Starts scanning once Bluetooth is powered on.
    public func start() {
      queue.async { [weak self] in
        guard let self, !finished, manager == nil else { return }
        manager = CBCentralManager(
          delegate: self, queue: queue,
          options: [CBCentralManagerOptionShowPowerAlertKey: false])
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

    /// Disconnects and ends the link.
    public func cancel() {
      queue.async { [weak self] in self?.finish(.cancelled) }
    }

    /// Ends the link once: indications off first, so the custodian sees
    /// the link end even while the system keeps the connection for
    /// another client.
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
        if let peripheral {
          if let channel, channel.isNotifying {
            peripheral.setNotifyValue(false, for: channel)
          }
          manager.cancelPeripheralConnection(peripheral)
        }
      }
      onEvent(.trace(.ended(failure)))
      onEvent(.closed(failure))
    }

    /// Writes the routing preamble as one SINGLE fragment (§5.2).
    internal func sendPreamble() {
      do {
        outbound = try RappBleSar.segment(try purpose.preamble(), capacity: capacity)
      } catch {
        finish(.protocolViolation)
        return
      }
      writeNext()
    }

    internal func valueUpdated(_ characteristic: CBCharacteristic, error: (any Error)?) {
      guard error == nil, let value = characteristic.value else {
        finish(.protocolViolation)
        return
      }
      if characteristic.uuid == bootstrap?.uuid, !routed {
        onEvent(.bootstrap(value))
        sendPreamble()
        return
      }
      if characteristic.uuid == bootstrap?.uuid, rereadingBootstrap {
        onEvent(.attemptRefused(value))
        finish(.attemptRefused)
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
        finish(.reassemblyFailed)
      }
    }

    /// The custodian answered a write; before routing, a refusal answers
    /// the preamble, and after it, ATT error Insufficient Resources refuses CPace
    /// step 1, which sends the requester back to the bootstrap
    /// characteristic (§4.2, "Busy Refusal" item 2).
    internal func wrote(error: (any Error)?) {
      guard !finished, !rereadingBootstrap else { return }
      if routed, purpose == .pairing,
        (error as? CBATTError)?.code == .insufficientResources,
        let peripheral, let bootstrap
      {
        rereadingBootstrap = true
        outbound.removeAll()
        peripheral.readValue(for: bootstrap)
        return
      }
      guard error == nil, !outbound.isEmpty else {
        // Before routing only the custodian's own refusal of the write is a
        // refusal; a link that dropped under the write is lost, and the
        // phone may be dialled again at once.
        let refused = !routed && (error as? CBATTError)?.code == .writeNotPermitted
        finish(refused ? .routingRefused : .disconnected)
        return
      }
      outbound.removeFirst()
      guard routed else {
        guard outbound.isEmpty else {
          writeNext()
          return
        }
        routed = true
        onEvent(.trace(.preambleAccepted))
        onEvent(.connected)
        return
      }
      writeNext()
    }

    internal func disconnected() {
      finish(.disconnected)
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

    private func armTimer() {
      queue.asyncAfter(
        deadline: .now() + .milliseconds(Int(RappBleSar.reassemblyTimeoutMilliseconds))
      ) { [weak self] in
        guard let self, !finished else { return }
        do {
          try reassembler.checkTimer(
            nowMilliseconds: RappPlatformClock().monotonicMilliseconds())
        } catch {
          finish(.reassemblyFailed)
        }
      }
    }
  }
#endif
