// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(CoreBluetooth) && !os(macOS)
  import CoreBluetooth

  /// Manages a Bluetooth Low Energy RAPP session under the `fi.refineid.ble.v1` profile.
  ///
  /// Supports both Central (requester/dialer) and Peripheral (proxy/holder/listener) roles
  /// using BLE L2CAP Connection-Oriented Channels.
  public final class BleRelaySession: NSObject, @unchecked Sendable {
    // MARK: - Constants

    internal enum Constants {
      internal static let psmByteCount = 2
      internal static let psmCharacteristicUUIDString = "FA1D0004-C34A-4836-843B-7603B5749A32"
    }

    // MARK: - Role

    /// The role this BLE session executes (Central dialer vs Peripheral listener).
    public enum Mode {
      case central(endpoint: BleRelayEndpoint, preamble: Data)
      case peripheral(serviceUUID: String)
    }

    // MARK: - Properties

    internal let mode: Mode
    internal let onEvent: @Sendable (BleRelayEvent) -> Void
    internal let queue = DispatchQueue(label: "fi.refineid.ble-relay-session")

    internal var centralManager: CBCentralManager?
    internal var peripheralManager: CBPeripheralManager?
    internal var connectedPeripheral: CBPeripheral?
    internal var channelHandler: BleL2CAPChannelHandler?

    internal var isCancelled = false
    internal var isConnected = false
    internal var assignedPsm: UInt16?

    // MARK: - Initialization

    /// Creates a Central (dialer) BLE session targeting the given endpoint.
    @preconcurrency
    public init(
      endpoint: BleRelayEndpoint,
      preamble: Data,
      onEvent: @escaping @Sendable (BleRelayEvent) -> Void
    ) {
      self.mode = .central(endpoint: endpoint, preamble: preamble)
      self.onEvent = onEvent
      super.init()
    }

    /// Creates a Peripheral (listener) BLE session advertising the given service UUID.
    @preconcurrency
    public init(
      serviceUUID: String = BleRelayEndpoint().serviceUUIDString,
      onEvent: @escaping @Sendable (BleRelayEvent) -> Void
    ) {
      self.mode = .peripheral(serviceUUID: serviceUUID)
      self.onEvent = onEvent
      super.init()
    }

    // MARK: - Public API

    /// Starts Central scanning or Peripheral advertising.
    public func start() {
      queue.async { [weak self] in
        guard let self, !isCancelled else { return }
        switch mode {
        case .central:
          centralManager = CBCentralManager(delegate: self, queue: queue)

        case .peripheral:
          peripheralManager = CBPeripheralManager(delegate: self, queue: queue)
        }
      }
    }

    /// Sends one opaque RAPP frame over the open L2CAP channel.
    public func send(_ frame: Data) async throws {
      guard let handler = queue.sync(execute: { self.channelHandler }) else {
        throw BleRelayTransportError.notConnected
      }
      try await handler.send(frame)
    }

    /// Cancels the session, disconnecting and stopping all radios.
    public func cancel() {
      queue.async { [weak self] in
        guard let self, !isCancelled else { return }
        isCancelled = true

        if let handler = channelHandler {
          Task { await handler.close() }
          channelHandler = nil
        }

        if let central = centralManager {
          if central.isScanning {
            central.stopScan()
          }
          if let peripheral = connectedPeripheral {
            central.cancelPeripheralConnection(peripheral)
          }
        }

        if let manager = peripheralManager {
          if manager.isAdvertising {
            manager.stopAdvertising()
          }
          if let psm = assignedPsm {
            manager.unpublishL2CAPChannel(CBL2CAPPSM(psm))
          }
          manager.removeAllServices()
        }

        connectedPeripheral = nil
        onEvent(.closed(.cancelled))
      }
    }

    internal func finish(with error: BleRelayTransportError) {
      guard !isCancelled else { return }
      isCancelled = true
      onEvent(.closed(error))
    }
  }
#endif
